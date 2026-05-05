
# Telegram to SimpleX bridge forwards messages from Telegram channels (via a bot) into a SimpleX group.
import asyncio
import json
import logging
import os
import sqlite3
import uuid
from collections import defaultdict
from pathlib import Path
import websockets
from dotenv import load_dotenv
from telegram import Update
from telegram.constants import MessageOriginType
from telegram.ext import (
    Application,
    CommandHandler,
    ContextTypes,
    MessageHandler,
    filters,
)

# ----------------------- configs -----------------------

load_dotenv()
TG_TOKEN = os.environ["TELEGRAM_TOKEN"]
PASSWORD = os.environ["BRIDGE_PASSWORD"]
SIMPLEX_WS = os.environ.get("SIMPLEX_WS", "ws://127.0.0.1:5225")
SIMPLEX_GROUP_ID = int(os.environ["SIMPLEX_GROUP_ID"])
SIMPLEX_GROUP_NAME = os.environ["SIMPLEX_GROUP_NAME"]
TMP_DIR = Path(os.environ.get("TMP_DIR", "/tmp/tg-simplex"))
TMP_DIR.mkdir(parents=True, exist_ok=True)

AUTH_DB = Path(__file__).parent / "auth.db"

ALBUM_DEBOUNCE_SECONDS = 2.0

logging.basicConfig(
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    level=logging.INFO,
)
log = logging.getLogger("bridge")
logging.getLogger("httpx").setLevel(logging.WARNING)
logging.getLogger("telegram").setLevel(logging.INFO)
logging.getLogger("websockets").setLevel(logging.INFO)

# ----------------------- authentication storage -----------------------
#  stores an sqlite3 database with users authentified to send messages via bot
def _db():
    conn = sqlite3.connect(AUTH_DB)
    conn.execute(
        "CREATE TABLE IF NOT EXISTS authed_users "
        "(user_id INTEGER PRIMARY KEY, added_at TEXT DEFAULT CURRENT_TIMESTAMP)"
    )
    return conn

def is_authed(user_id: int) -> bool:
    with _db() as conn:
        row = conn.execute(
            "SELECT 1 FROM authed_users WHERE user_id=?", (user_id,)
        ).fetchone()
    return row is not None

def authorize(user_id: int):
    with _db() as conn:
        conn.execute(
            "INSERT OR IGNORE INTO authed_users (user_id) VALUES (?)", (user_id,)
        )

# ----------------------- SimpleX client -----------------------

class SimplexClient:
    #Persistent WebSocket connection to simplex-chat CLI.
    def __init__(self, url: str):
        self.url = url
        self.ws = None
        self._lock = asyncio.Lock()

    async def connect(self):
        self.ws = await websockets.connect(self.url, max_size=None)
        log.info("Connected to SimpleX at %s", self.url)

    async def _send_cmd(self, cmd: str) -> dict:
        async with self._lock:
            if self.ws is None:
                await self.connect()
            corr_id = uuid.uuid4().hex
            payload = json.dumps({"corrId": corr_id, "cmd": cmd})
            log.info("CLI -> %s", cmd[:300])
            try:
                await self.ws.send(payload)
            except (websockets.ConnectionClosed, AttributeError):
                log.warning("WebSocket closed, reconnecting")
                await self.connect()
                await self.ws.send(payload)
            for _ in range(50):
                raw = await asyncio.wait_for(self.ws.recv(), timeout=30)
                msg = json.loads(raw)
                if msg.get("corrId") == corr_id:
                    resp_type = msg.get("resp", {}).get("type", "?")
                    log.info("CLI <- %s", resp_type)
                    if resp_type in ("chatCmdError", "chatError", "errorStore", "error"):
                        log.error("CLI error response: %s", json.dumps(msg, indent=2)[:1500])
                    return msg
            raise RuntimeError("Did not receive matching response")

    async def send_text(self, group_id: int, text: str):
        cmd = f"/_send #{group_id} text {text}"
        return await self._send_cmd(cmd)
    async def send_file(self, group_id: int, file_path: str, caption: str = "", media_type: str = "file"):
        if caption:
            await self._send_cmd(f"/_send #{group_id} text {caption}")
        if media_type == "image":
            cmd = f"/image #'{SIMPLEX_GROUP_NAME}' {file_path}"
        else:
            cmd = f"/f #'{SIMPLEX_GROUP_NAME}' {file_path}"
        return await self._send_cmd(cmd)

simplex = SimplexClient(SIMPLEX_WS)

# ----------------------- Telegram handlers -----------------------

album_buffers: dict[str, list] = defaultdict(list)
album_tasks: dict[str, asyncio.Task] = {}

async def cmd_start(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    user = update.effective_user
    if is_authed(user.id):
        await update.message.reply_text(
            "✅ You're already authorized. Just forward messages to me and I'll relay them."
        )
        return

    args = ctx.args or []
    if len(args) == 1 and args[0] == PASSWORD:
        authorize(user.id)
        log.info("Authorized user_id=%s username=%s", user.id, user.username)
        await update.message.reply_text(
            "✅ Successfull authorization. Forward channel posts to me and I'll relay them to SimpleX."
        )
    else:
        await update.message.reply_text(
            "🔒 This bot is restricted. Send `/start <password>` to authorize.",
            parse_mode="Markdown",
        )

async def cmd_whoami(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    user = update.effective_user
    await update.message.reply_text(
        f"user_id: `{user.id}`\nauthorized: {is_authed(user.id)}",
        parse_mode="Markdown",
    )

def build_attribution(message) -> str:
    origin = message.forward_origin
    lines = []

    if origin is None:
        return ""

    if origin.type == MessageOriginType.CHANNEL:
        chat = origin.chat
        title = chat.title or "channel"
        lines.append(f"📰 {title}")
        if chat.username:
            link = f"https://t.me/{chat.username}/{origin.message_id}"
            lines.append(f"🔗 {link}")
        if origin.author_signature:
            lines.append(f"✍️ {origin.author_signature}")

    elif origin.type == MessageOriginType.CHAT:
        title = origin.sender_chat.title or "chat"
        lines.append(f"💬 {title}")

    elif origin.type == MessageOriginType.USER:
        u = origin.sender_user
        name = u.full_name or u.username or "user"
        lines.append(f"👤 {name}")

    elif origin.type == MessageOriginType.HIDDEN_USER:
        lines.append(f"👤 {origin.sender_user_name}")

    return "\n".join(lines)

def message_body(message) -> str:
    return message.caption or message.text or ""

async def download_media(message, ctx) -> tuple[str, str] | tuple[None, None]:
    file = None
    suffix = ""
    media_type = "file"

    if message.photo:
        file = await message.photo[-1].get_file()
        suffix = ".jpg"
        media_type = "image"
    elif message.video:
        file = await message.video.get_file()
        suffix = ".mp4"
        media_type = "video"
    elif message.animation:
        file = await message.animation.get_file()
        suffix = ".mp4"
        media_type = "video"
    elif message.document:
        file = await message.document.get_file()
        suffix = "_" + (message.document.file_name or "file")
        media_type = "file"
    elif message.audio:
        file = await message.audio.get_file()
        suffix = ".mp3"
        media_type = "audio"
    elif message.voice:
        file = await message.voice.get_file()
        suffix = ".ogg"
        media_type = "audio"
    elif message.video_note:
        file = await message.video_note.get_file()
        suffix = ".mp4"
        media_type = "video"
    if file is None:
        return None, None

    fname = TMP_DIR / f"{uuid.uuid4().hex}{suffix}"
    try:
        await file.download_to_drive(fname)
        return str(fname), media_type
    except Exception as e:
        log.warning("Download failed: %s", e)
        return None, None

async def relay_single(message, ctx):
    attribution = build_attribution(message)
    body = message_body(message)
    full_text = (attribution + ("\n\n" + body if body else "")).strip()
    media_path, media_type = await download_media(message, ctx)
    log.info("Downloaded media to: %s (type: %s)", media_path, media_type)
    try:
        if media_path:
            resp = await simplex.send_file(
                SIMPLEX_GROUP_ID, media_path, caption=full_text, media_type=media_type
            )
            resp_type = resp.get("resp", {}).get("type", "?")
            if resp_type in ("chatCmdError", "chatError", "errorStore", "error"):
                raise RuntimeError(f"SimpleX rejected file send: {resp_type}")
        else:
            if full_text:
                resp = await simplex.send_text(SIMPLEX_GROUP_ID, full_text)
                resp_type = resp.get("resp", {}).get("type", "?")
                if resp_type in ("chatCmdError", "chatError", "errorStore", "error"):
                    raise RuntimeError(f"SimpleX rejected text send: {resp_type}")
            else:
                log.info("Skipping empty message")
    finally:
        if media_path:
            try:
                os.unlink(media_path)
            except OSError:
                pass

async def flush_album(media_group_id: str, ctx):
    await asyncio.sleep(ALBUM_DEBOUNCE_SECONDS)
    items = album_buffers.pop(media_group_id, [])
    album_tasks.pop(media_group_id, None)
    if not items:
        return

    first = items[0]
    attribution = build_attribution(first)
    captions = [m.caption for m in items if m.caption]
    body = "\n\n".join(captions)
    full_text = (attribution + ("\n\n" + body if body else "")).strip()

    log.info("Flushing album %s with %d items", media_group_id, len(items))

    if full_text:
        try:
            await simplex.send_text(SIMPLEX_GROUP_ID, full_text)
        except Exception as e:
            log.exception("Album text send failed: %s", e)

    for msg in items:
        path, mtype = await download_media(msg, ctx)
        if path:
            try:
                await simplex.send_file(SIMPLEX_GROUP_ID, path, caption="", media_type=mtype)
            except Exception as e:
                log.exception("Album media send failed: %s", e)
            finally:
                try:
                    os.unlink(path)
                except OSError:
                    pass

async def on_forwarded(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    msg = update.message
    user = update.effective_user

    if not is_authed(user.id):
        await msg.reply_text("🔒 Not authorized. Send `/start <password>` first.",
                             parse_mode="Markdown")
        return

    if msg.media_group_id:
        gid = msg.media_group_id
        album_buffers[gid].append(msg)
        if gid not in album_tasks:
            album_tasks[gid] = asyncio.create_task(flush_album(gid, ctx))
        return

    try:
        await relay_single(msg, ctx)
        await msg.reply_text("✅ Relayed", quote=False)
    except Exception as e:
        log.exception("Relay failed: %s", e)
        await msg.reply_text(f"❌ Relay failed: {e}")


# ----------------------- main -----------------------

async def post_init(app):
    await simplex.connect()
    log.info("Bridge ready. Authed users: %d",
             _db().execute("SELECT COUNT(*) FROM authed_users").fetchone()[0])

def main():
    app = (
        Application.builder()
        .token(TG_TOKEN)
        .post_init(post_init)
        .build()
    )

    app.add_handler(CommandHandler("start", cmd_start))
    app.add_handler(CommandHandler("whoami", cmd_whoami))
    app.add_handler(
        MessageHandler(filters.ALL & ~filters.COMMAND, on_forwarded)
    )

    log.info("Starting Telegram polling")
    app.run_polling(allowed_updates=Update.ALL_TYPES)

if __name__ == "__main__":
    main()