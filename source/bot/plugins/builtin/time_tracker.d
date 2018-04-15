module bot.plugins.builtin.time_tracker;

import bot.irc.bot;
import bot.plugins.manager;
import bot.plugins.midware.router;
import bot.util.userstore;
import bot.twitch.stream;

import vibe.vibe;

import core.time;
import std.string;
import std.conv;
import std.math;
import std.typecons;

string digit2(string n) {
	return n.length < 2 ? '0' ~ n : n;
}

string formatWatchTime(long time) {
	auto hours = time / 60;
	auto minutes = time % 60;
	return hours.to!string ~ "h" ~ minutes.to!string.digit2 ~ "m";
}

string compactWatchTime(long time) {
	if (time < 100)
		return time.to!string ~ "m";
	else
		return (round(time / 6.0) / 10.0).to!string ~ "h";
}

class TimeTrackerPlugin : IPlugin {
	this(string websiteBase, string ignoreUser, bool rewardActive, int minutesPerPoint = 10) {
		this.websiteBase = websiteBase;
		this.rewardActive = rewardActive;
		auto router = new CommandRouter();
		router.on("!points", &getPoints, "Check your current points");
		router.on("!p", &getPoints);
		router.on("!give :user :amount", &onGive, "Give $user $amount of points");
		router.on("!leaderboard", &getAllPoints, "Get the leaderbord for the channel");
		//router.on("!import :url", &importPoints);
		use(router);

		liveChanged ~= &onLiveChange;

		runTask({
			int minute = 0;
			while (true) {
				sleep(1.minutes);
				minute++;
				bool givePoints = false;
				if (minute >= minutesPerPoint) {
					minute = 0;
					givePoints = true;
				}
				foreach (ref multiplier; multipliers) {
					if (!included.canFind(multiplier.channel))
						included ~= multiplier.channel.toLower[1 .. $];
					if (!multiplier.channel.isLive || multiplier.username.toLower == ignoreUser.toLower)
						continue;
					if (multiplier.multiplier > 0 && givePoints) {
						multiplier.userID.pointsFor(multiplier.channel, +multiplier.multiplier);
						multiplier.multiplier = max(1, multiplier.multiplier - 1);

						if (multiplier.username == multiplier.channel)
							multiplier.multiplier = max(multiplier.multiplier, 5);
					}
					multiplier.userID.watchTimeFor(multiplier.channel, +1);
				}
			}
		});
	}

	string[] included;
	void onLiveChange(string channel, bool live) {
		if (bot && included.canFind(channel.toLower))
			bot.send('#' ~ channel, live ? "Channel is now live, tracking points" : "Channel no longer live, stopped tracking points.");
	}

	Abort getPoints(IBot bot, string channel, scope Command command) {
		bot.send(channel, "@" ~ command.raw.sender ~ " points: " ~ command.raw.senderID.pointsFor(channel)
				.to!string ~ " (watched for " ~ command.raw.senderID.watchTimeFor(channel).compactWatchTime ~ ")");
		return Abort.yes;
	}

	Abort onGive(IBot bot, string channel, scope Command command) {
		long amount = 0;
		try {
			amount = command.params["amount"].to!long;
		}
		catch (ConvException) {
			amount = 0;
		}
		string toUser = command.params["user"];
		if (amount <= 0)
			bot.send(channel, "@" ~ command.raw.sender ~ " use `!give :user :amount`, where $amount is a positive non-zero integer, to give $amount of points to $user. (You need to own at least $amount points)");
		else {
			long current = command.raw.senderID.pointsFor(channel);
			if (amount > current)
				bot.send(channel, "@" ~ command.raw.sender ~ " you don't have the required amount of points.");
			else {

				long toUserID;
				try {
					import bot.twitch.userids : useridFor;

					toUserID = useridFor(toUser);
				}
				catch (Exception e) {
					bot.send(channel, "@" ~ command.raw.sender ~ ", Could not find '" ~ toUser ~ "'");
					return Abort.yes;
				}

				auto newAmount = command.raw.senderID.pointsFor(channel, -amount);
				toUserID.pointsFor(channel, amount);
				bot.send(channel, format("@%s gave @%s %d points. Has %d points left!", command.raw.sender, toUser, amount, newAmount));
			}
		}
		return Abort.yes;
	}

	Abort getAllPoints(IBot bot, string channel, scope Command command) {
		bot.send(channel, "View the current leaderboard on " ~ websiteBase ~ channel[1 .. $] ~ "/points");
		return Abort.yes;
	}

	Abort importPoints(IBot bot, string channel, scope Command command) {
		if (command.raw.senderRank < Rank.mod) {
			return Abort.no;
		}
		string url = command.params["url"];
		if (url == "confirm") {
			if (lastURL.length < 5 || lastURL[0 .. 4] != "http") {
				bot.send(channel, "Use `!import <url>` first");
			} else {
				try {
					string ret;
					requestHTTP(lastURL, (scope req) {  }, (scope res) {
						if (res.statusCode == 200)
							ret = res.bodyReader.readAllUTF8(false, 1024 * 1024 * 40);
					});
					if (!ret.length) {
						bot.send(channel, "Could not download points.");
						return Abort.yes;
					}
					import std.csv : csvReader;

					try {
						auto reader = ret.csvReader!(Tuple!(string, long, long, long))(["Username", "Twitch User ID",
								"Current Points", "All Time Points"]);
						foreach (entry; reader) {
							import bot.twitch.userids;

							entry[1].overridePointsFor(channel, entry[2]);
							entry[1].overrideWatchTimeFor(channel, entry[3]);
							updateUser(entry[0], entry[1]);
						}
						bot.send(channel, "Successfully imported data.");
					}
					catch (Exception e) {
						logError("Invalid data format: %s", e);
						bot.send(channel, "Data not in valid format. Can only import revlobot points.");
					}
				}
				catch (Exception e) {
					logError("Download error: %s", e);
					bot.send(channel, "Could not download points. Error during download.");
				}
			}
		} else {
			lastURL = url;
			if (url != "cancel")
				bot.send(channel, "This is about to replace the current leaderboards. Type `!import confirm` to confirm");
		}
		return Abort.yes;
	}

	string lastURL;

	override void onActive(IBot bot, CommonMessage msg) {
		put(msg.target[1 .. $], msg.sender, msg.senderID, 10 * (msg.isSubscriber ? 2 : 1));
	}

	override Abort onMessage(IBot bot, CommonMessage msg) {
		if (rewardActive)
			onActive(bot, msg);
		return Abort.no;
	}

	override void onUserJoin(IBot bot, string channel, string username) {
		import bot.twitch.userids : useridFor;

		int startMultiplier = 0; // User must write atleast one message before gaining points

		if (username == channel)
			startMultiplier = 5;
		put(channel, username, useridFor(username), startMultiplier);
		this.bot = bot;
	}

	override void onUserLeave(IBot, string channel, string username) {
		foreach_reverse (i, multiplier; multipliers) {
			if (multiplier.username == username) {
				if (!channel.length || multiplier.channel == channel) {
					multipliers[i] = multipliers[$ - 1];
					multipliers.length--;
				}
			}
		}
	}

	void put(string channel, string username, long userID, int newMultiplier) {
		bool found;

		foreach (ref multiplier; multipliers) {
			if (multiplier.channel == channel && multiplier.userID == userID) {
				found = true;
				multiplier.username = username;
				multiplier.multiplier = newMultiplier;
				break;
			}
		}
		if (!found)
			multipliers ~= ChannelMultiplier(channel, userID, username, newMultiplier);
	}

private:
	bool rewardActive;
	string websiteBase;
	public ChannelMultiplier[] multipliers;
	IBot bot;
}

struct ChannelMultiplier {
	string channel;
	long userID;
	string username;
	int multiplier;
}
