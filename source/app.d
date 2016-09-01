import vibe.vibe;

import bot.irc.bot;
import bot.plugins.manager;
import bot.plugins.builtin.test;
import bot.plugins.builtin.twitch_highlight;
import bot.plugins.builtin.custom_commands;

import std.file;

IRCBot twitch;
PluginManager plugins;

HighlightPlugin highlightsPlugin;

shared static this()
{
	version (unittest)
	{
	}
	else
	{
		auto settings = new HTTPServerSettings;
		settings.port = 2030;
		settings.bindAddresses = ["::1", "127.0.0.1"];

		auto info = parseJsonString(readText("info.json"));
		twitch = new IRCBot("irc.twitch.tv", info["username"].get!string,
				info["password"].get!string);
		string[] channels;
		foreach (channel; info["channels"].get!(Json[]))
			channels ~= channel.get!string;
		string website = info["website"].get!string;
		twitch.join(channels);

		plugins = new PluginManager();
		plugins.bind(twitch);

		auto db = connectMongoDB("localhost").getDatabase("spamguard");

		//plugins.add(new TestPlugin());
		plugins.add(new CustomCommandsPlugin(db));
		plugins.add(highlightsPlugin = new HighlightPlugin(website));

		auto router = new URLRouter;
		router.get("/:user/highlights", &userHighlights);
		router.get("*", serveStaticFiles("./public/"));

		listenHTTP(settings, router);
	}
}

void userHighlights(HTTPServerRequest req, HTTPServerResponse res)
{
	string name = req.params["user"];
	auto highlights = highlightsPlugin.getChannelOrThrow("#" ~ name);
	res.render!("highlights.dt", name, highlights, make2);
}
