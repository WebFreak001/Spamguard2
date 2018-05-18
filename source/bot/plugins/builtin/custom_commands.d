module bot.plugins.builtin.custom_commands;

import bot.irc.bot;
import bot.plugins.manager;
import bot.plugins.midware.router;

import std.algorithm;
import std.ascii;
import std.array;

import vibe.db.mongo.database;
import vibe.db.mongo.collection;
import vibe.data.bson;

import mongoschema;

struct CommandInfo
{
    mixin MongoSchema;

    string channel;
    string trigger;
    string message;
    bool modOnly;
}

class CustomCommandsPlugin : IPlugin
{
    this(MongoDatabase db)
    {
        db["commands"].register!CommandInfo;
        commands = CommandInfo.findAll().array;

        auto router = new CommandRouter();
        router.on("!command add :trigger :msg", &addCommand);
        router.on("!command remove :trigger", &removeCommand);
        router.on("!command reload", &reloadCommands);
        router.on("!help command", &help);
        use(router);
    }

    Abort addCommand(IBot bot, string channel, scope Command cmd)
    {
        if (cmd.raw.senderRank < Rank.mod)
        {
            return Abort.yes;
        }
        CommandInfo command;
        command.modOnly = !!("m" in cmd.flags);
        command.channel = channel;
        command.trigger = cmd.params["trigger"];
        command.message = cmd.params["msg"];
        command.save();
        commands ~= command;
        bot.send(channel, "Command '" ~ command.trigger ~ "' created");
        return Abort.yes;
    }

    Abort removeCommand(IBot bot, string channel, scope Command command)
    {
        if (command.raw.senderRank < Rank.mod)
        {
            return Abort.yes;
        }
        CommandInfo found;
        size_t index = -1;
        string trigger = command.params["trigger"];
        foreach (i, cmd; commands)
            if (cmd.trigger == trigger)
            {
                found = cmd;
                index = i;
                break;
            }
        if (index != -1)
        {
            if (found.remove())
            {
                commands = commands.remove(index);
                bot.send(channel,
                        "Command '" ~ found.trigger ~ "' with message '"
                        ~ found.message ~ "' removed");
            }
            else
            {
                bot.send(channel, "Could not remove command '" ~ found.trigger ~ "'");
            }
        }
        else
            bot.send(channel, "Command trigger not found");
        return Abort.yes;
    }

    Abort reloadCommands(IBot bot, string channel, scope Command command)
    {
        if (command.raw.senderRank < Rank.admin)
        {
            return Abort.yes;
        }
        commands = CommandInfo.findAll().array;
        return Abort.yes;
    }

    Abort help(IBot bot, string channel, scope Command)
    {
        bot.send(channel,
                "!command - command management - Usage: !command (add [-m] <trigger> <msg>|remove <trigger>)");
        return Abort.yes;
    }

    override Abort onMessage(IBot bot, CommonMessage msg)
    {
        foreach (command; commands.filter!(a => a.channel == msg.target))
        {
            if (msg.message.startsWith(command.trigger))
            {
                if (msg.message.length > command.trigger.length)
                {
                    if (!msg.message[command.trigger.length].isWhite)
                        continue;
                }
                if (command.modOnly && msg.senderRank < Rank.mod)
                    continue;
                bot.send(msg.target, command.message);
                return Abort.yes;
            }
        }
        return Abort.no;
    }

    override void onUserJoin(IBot, string channel, string username)
    {
    }

    override void onUserLeave(IBot, string channel, string username)
    {
    }

private:
    CommandInfo[] commands;
}
