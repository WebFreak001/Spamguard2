# spamguard2

Twitch bot written in D

## Usage

Create a file named `info.json` with following content and replace placeholders accordingly:

```json
{
	"username": "<Your Twitch Username>",
	"password": "<Your Twitch Chat OAuth token>",
	"channels": [
		"#<Channel name>"
	],
	"website": "<Website for some commands>"
}
```

Compile & Run

```sh
dub run
```