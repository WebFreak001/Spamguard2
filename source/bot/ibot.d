module bot.ibot;

import bot.types;

import core.time;

alias MessageHandler = void delegate(IBot, CommonMessage);
alias UserHandler = void delegate(IBot, string channel, string username);

interface IBot
{
    void kick(string channel, string user, Duration duration);
    void ban(string channel, string user);
    void unban(string channel, string user);

    final void send(string channel, string message)
    {
        CommonMessage msg;
        msg.target = channel;
        msg.message = message;
        send(msg);
    }

    void send(CommonMessage message);
    void addOnMessage(MessageHandler handler);
    void addOnJoin(UserHandler handler);
    void addOnLeave(UserHandler handler);
}
