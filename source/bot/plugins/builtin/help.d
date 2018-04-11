module bot.plugins.builtin.help;

import bot.plugins.manager;
import bot.plugins.midware.router;

import std.conv;

import vibe.core.log;

class HelpPlugin : IPlugin {
public:
	this(PluginManager pm) {
		_pm = pm;
		auto router = new CommandRouter();
		router.on("!help", &help, "Get link to wiki");
		router.on("!h", &help);
		router.on("!commands", &help);
		use(router);
	}

	Abort help(IBot bot, string channel, scope Command command) {
		import std.algorithm : map, joiner;
		import std.outbuffer : OutBuffer;

		if (false) { // TODO: Generate markdown for wiki
			string output = "|";
			foreach (PatternCallback p; _pm.plugins.map!(a => a.midwares).joiner.map!(a => cast(CommandRouter)a).map!(a => a.patterns).joiner)
				if (p.description)
					output ~= "\t" ~ p.rawFormat ~ ": " ~ p.description ~ "\t|";

			bot.send(channel, output);
		} else {
			bot.send(channel, "https://github.com/Vild/Spamguard2/wiki/Commands");
		}

		return Abort.yes;
	}

	override Abort onMessage(IBot, CommonMessage) {
		return Abort.no;
	}

	override void onUserJoin(IBot, string channel, string username) {
	}

	override void onUserLeave(IBot, string channel, string username) {
	}

private:
	PluginManager _pm;
}
