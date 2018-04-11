import vibe.vibe;

import bot.irc.bot;
import bot.plugins.manager;
import bot.plugins.builtin.test;
import bot.plugins.builtin.twitch_highlight;
import bot.plugins.builtin.custom_commands;
import bot.plugins.builtin.time_tracker;
import bot.plugins.builtin.gambler;
import bot.plugins.builtin.help;
import bot.twitch.api;
import bot.twitch.userids;
import bot.util.userstore;

import std.algorithm;
import std.file;

string[] channels;
IRCBot twitch;
PluginManager plugins;

HighlightPlugin highlightsPlugin;
TimeTrackerPlugin timeTrackerPlugin;

shared static this() {
	highlightsPlugin.destroy;
	plugins.destroy;
	twitch.destroy;
}

shared static this() {
	version (unittest) {
	} else {
		auto settings = new HTTPServerSettings;
		settings.port = 2030;
		settings.bindAddresses = ["::1", "127.0.0.1"];

		auto info = parseJsonString(readText("info.json"));
		TwitchAPI.clientID = info["clientid"].get!string;
		twitch = new IRCBot("irc.twitch.tv", info["username"].get!string, info["password"].get!string);
		foreach (channel; info["channels"].get!(Json[]))
			channels ~= channel.get!string;
		string website = info["website"].get!string;
		twitch.join(channels);

		plugins = new PluginManager();
		plugins.bind(twitch);

		auto db = connectMongoDB("127.0.0.1").getDatabase("spamguard");
		db.setupUserStore();

		version (ShouldConvertDB)
			foreach (channel; channels)
				foreach (user; ChannelUserStorage._schema_collection_.find()) {
					auto i = user["identifier"];
					auto MEINUSAIFHNIDSFIJSIFJISD = i.tryIndex("username");
					if (!MEINUSAIFHNIDSFIJSIFJISD.isNull) {
						import mongoschema;

						string username = MEINUSAIFHNIDSFIJSIFJISD.get.get!string;

						struct TargetUserName {
							string username;
							string channel;
						}

						auto store = fromSchemaBson!ChannelUserStorage(user);
						long userID = useridFor(username);
						if (userID == long.min) {
							logInfo("Can't update user: '%s', Removing!", username);
							continue;
						}
						store.identifier = Target(userID, channel);
						store.save();
					}
				}

		plugins.add(new HelpPlugin(plugins));
		plugins.add(timeTrackerPlugin = new TimeTrackerPlugin(website, info["username"].get!string, true, 1));
		plugins.add(new CustomCommandsPlugin(db));
		plugins.add(new GamblerPlugin());

		auto router = new URLRouter;
		router.get("/", &index);
		//router.get("/:user/highlights", &userHighlights);
		router.get("/:user/points", &userPoints);
		router.get("/:user/points/data", &userPoints_data);
		router.get("*", serveStaticFiles("./public/"));

		listenHTTP(settings, router);
	}
}

void index(HTTPServerRequest req, HTTPServerResponse res) {
	res.render!("index.dt", channels);
}

void userPoints(HTTPServerRequest req, HTTPServerResponse res) {
	string name = req.params["user"];
	res.render!("points.dt", name);
}

void userPoints_data(HTTPServerRequest req, HTTPServerResponse res) {
	string name = req.params["user"];
	struct UserPointsWatchTime {
		string username;
		long points;
		long watchTime;
		int multiplier;
	}

	UserPointsWatchTime[] allUsers;
	foreach (entry; ChannelUserStorage.findRange(["identifier.channel" : name])) {
		if (entry.info.type == Bson.Type.object && entry.identifier.userID) {
			auto propPtr = "properties" in entry.info.get!(Bson[string]);
			if (propPtr && propPtr.type == Bson.Type.object) {
				auto properties = *propPtr;
				auto pointsPtr = "points" in properties.get!(Bson[string]);
				auto timePtr = "watchTime" in properties.get!(Bson[string]);
				if (timePtr && timePtr.type == Bson.Type.long_) {
					auto time = timePtr.get!long;
					long points = 0;
					if (pointsPtr && pointsPtr.type == Bson.Type.long_)
						points = pointsPtr.get!long;
					try {
						auto username = usernameFor(entry.identifier.userID);
						if (username == "nightbot" || username == "zeptus")
							continue;

						import std.algorithm : find;

						auto mUser = find!"a.username == b"(timeTrackerPlugin.multipliers, username);
						if (mUser.empty)
							continue;

						allUsers ~= UserPointsWatchTime(username, points, time, mUser[0].multiplier);
					} catch (Exception) {
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
	res.render!("points_data.dt", users, formatWatchTime);
}
