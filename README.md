# Quick and dirty app to make your Tile trackers ring

This is in no way a correct implementation of the Tile protocol, rather a simple app, aimed at making the trackers ring without the official app. Use at your own risks.

## Getting Started

Retrieve your devices Mac addresses and auth keys.
This can be done with

https://github.com/bachya/pytile

```python
import asyncio

from aiohttp import ClientSession

from pytile import async_login


async def main() -> None:
    async with ClientSession() as session:
        api = await async_login("<email>", "<password>", session)
        tiles = await api.async_get_tiles()
        for tile in tiles.values():
            print(tile._tile_data["result"]["auth_key"])


asyncio.run(main())

```

Then, you can fill `example.env` with your values. The `name` field is used for display, pick whatever works for you.

Finally, you can run this app on your phone:

```bash
flutter run --dart-define-from-file example.env
```

And you can install the release version if you are satisfied:

```bash
flutter build apk --dart-define-from-file example.env
flutter install --release
```

## Platforms

This has only be tested on Android, it may or may not work on iOS. It will not work on other platforms.

This app requires bluetooth and location permissions.
