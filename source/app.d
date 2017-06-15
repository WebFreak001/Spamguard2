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

import std.algorithm;
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
		router.get("/", staticRedirect("https://github.com/WebFreak001/Spamguard2"));
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
	struct UserPointsWatchTime
	{
		string username;
		long points;
		long watchTime;
	}

	UserPointsWatchTime[] allUsers;
	foreach (entry; ChannelUserStorage.findRange(["identifier.channel" : name]))
	{
		if (entry.info.type == Bson.Type.object && entry.identifier.userID)
		{
			auto propPtr = "properties" in entry.info.get!(Bson[string]);
			if (propPtr && propPtr.type == Bson.Type.object)
			{
				auto properties = *propPtr;
				auto pointsPtr = "points" in properties.get!(Bson[string]);
				auto timePtr = "watchTime" in properties.get!(Bson[string]);
				if (timePtr && timePtr.type == Bson.Type.long_)
				{
					auto time = timePtr.get!long;
					long points = 0;
					if (pointsPtr && pointsPtr.type == Bson.Type.long_)
						points = pointsPtr.get!long;
					try
					{
						auto username = usernameFor(entry.identifier.userID);
						if (username == "nightbot" || username == "revlobot"
								|| username == "spamguard" || username == name.toLower)
							continue;
						allUsers ~= UserPointsWatchTime(username, points, time);
					}
					catch (Exception)
					{
					}
				}
			}
		}
	}
	auto users = allUsers.sort!((a, b) {
		if (a.watchTime == b.watchTime)
			return a.points > b.points;
		else
			return a.watchTime > b.watchTime;
	});
	res.render!("points.dt", name, users, formatWatchTime);
}
