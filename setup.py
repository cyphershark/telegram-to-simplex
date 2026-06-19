# setup.py (sketch — reuses SimplexClient from bridge.py)
import asyncio, re, secrets, json
from pathlib import Path
from bridge import SimplexClient   # your existing class

SIMPLEX_WS = "ws://127.0.0.1:5225"

async def join_and_detect(group_link: str) -> tuple[int, str]:
    sx = SimplexClient(SIMPLEX_WS)
    await sx.connect()

    # one-time profile bootstrap is harmless if already set
    await sx._send_cmd("/auto_accept on")

    # join the group FOR them — this is the `/c <link>` they'd otherwise type
    await sx._send_cmd(f"/c {group_link}")

    # poll /groups until the new group shows up, then parse id + name
    for _ in range(30):
        resp = await sx._send_cmd("/groups")
        gid, name = parse_groups(resp)     # pull the numeric id + display name
        if gid is not None:
            return gid, name
        await asyncio.sleep(1)
    raise RuntimeError("Group didn't appear after joining — check the link.")

def main():
    token = input("Telegram bot token: ").strip()
    pw = input("Bridge password (blank to generate): ").strip() or secrets.token_urlsafe(18)
    link = input("SimpleX group link: ").strip()

    gid, name = asyncio.run(join_and_detect(link))

    Path(".env").write_text(
        f"TELEGRAM_TOKEN={token}\n"
        f"BRIDGE_PASSWORD={pw}\n"
        f"SIMPLEX_WS={SIMPLEX_WS}\n"
        f"SIMPLEX_GROUP_ID={gid}\n"
        f"SIMPLEX_GROUP_NAME={name}\n"
        f"TMP_DIR=./tmp\n"
    )
    Path(".env").chmod(0o600)
    print(f"\n✓ Joined '{name}' (id {gid}). Password: {pw}\n  Run the bridge with: telegram-to-simplex start")