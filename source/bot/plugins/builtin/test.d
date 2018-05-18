module bot.plugins.builtin.test;

import bot.plugins.manager;
import bot.plugins.midware.router;

import std.conv;

import vibe.core.log;

class TestPlugin : IPlugin
{
    this()
    {
        auto router = new CommandRouter();
        router.on("!test :msg me", &testMe);
        router.on("!test :msg you", &testYou);
        router.on("!test :msg", &testAny);
        router.on("!test", &testNone);
        use(router);
    }

    Abort testMe(IBot bot, string channel, scope Command command)
    {
        return Abort.no;
    }

    Abort testYou(IBot bot, string channel, scope Command)
    {
        bot.send(channel, "Tested you!");
        return Abort.yes;
    }

    Abort testAny(IBot bot, string channel, scope Command command)
    {
        bot.send(channel, "Tested any and me! - Flags: " ~ command.flags.to!string
                ~ " - Params: " ~ command.params.to!string ~ " - Raw: " ~ command.raw.to!string);
        return Abort.yes;
    }

    Abort testNone(IBot bot, string channel, scope Command command)
    {
        bot.send(channel, "Try !test <msg> (opt: me|you)");
        return Abort.yes;
    }

    override Abort onMessage(IBot, CommonMessage)
    {
        return Abort.no;
    }

    override void onUserJoin(IBot, string channel, string username)
    {
    }

    override void onUserLeave(IBot, string channel, string username)
    {
    }
}
