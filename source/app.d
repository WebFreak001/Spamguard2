import vibe.vibe;

import bot.irc.bot;
import bot.plugins.manager;
import bot.plugins.builtin.test;
import bot.plugins.builtin.twitch_highlight;
import bot.plugins.builtin.custom_commands;
import bot.plugins.builtin.time_tracker;
import bot.plugins.builtin.gambler;
import bot.twitch.api;
import bot.twitch.userids;
import bot.util.userstore;

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
		TwitchAPI.clientID = info["clientid"].get!string;
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
		db.setupUserStore();

		//plugins.add(new TestPlugin());
		plugins.add(new TimeTrackerPlugin(website, info["username"].get!string, true, 1));
		plugins.add(new CustomCommandsPlugin(db));
		plugins.add(new GamblerPlugin);
		plugins.add(highlightsPlugin = new HighlightPlugin(website));

		auto router = new URLRouter;
		router.get("/:user/highlights", &userHighlights);
		router.get("/:user/points", &userPoints);
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

void userPoints(HTTPServerRequest req, HTTPServerResponse res)
{
	string name = req.params["user"];
	auto users = ChannelUserStorage.findRange(["identifier.channel" : name]);
	res.render!("points.dt", name, users, formatWatchTime);
}
