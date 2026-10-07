import asyncio
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import Thread

from playwright.async_api import async_playwright


HANDOFF_DIR = Path(__file__).resolve().parent
REFERENCE_DIR = HANDOFF_DIR.parent / "reference"


class QuietHandler(SimpleHTTPRequestHandler):
    def log_message(self, format, *args):
        pass


async def main():
    REFERENCE_DIR.mkdir(parents=True, exist_ok=True)
    server = ThreadingHTTPServer(
        ("127.0.0.1", 0),
        partial(QuietHandler, directory=str(HANDOFF_DIR))
    )
    thread = Thread(target=server.serve_forever, daemon=True)
    thread.start()

    async with async_playwright() as playwright:
        browser = await playwright.chromium.launch(channel="chrome", headless=True)
        try:
            page = await browser.new_page(
                viewport={"width": 390, "height": 844},
                device_scale_factor=1
            )
            await page.goto(
                f"http://127.0.0.1:{server.server_port}/Simpler%20Grants%20iOS.dc.html",
                wait_until="networkidle"
            )
            await page.evaluate("() => document.fonts.ready.then(() => true)")
            await page.wait_for_timeout(1000)

            for index in range(1, 15):
                screen_id = f"{index:02d}"
                screen = page.locator(f'[id="{screen_id}"]')
                if await screen.count() == 0:
                    raise RuntimeError(f"Design reference screen {screen_id} was not found")
                await screen.first.screenshot(path=str(REFERENCE_DIR / f"{screen_id}.png"))
        finally:
            await browser.close()
            server.shutdown()
            server.server_close()
            thread.join()


asyncio.run(main())
