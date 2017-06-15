module bot.types;

static import vibeirc;

enum Rank : ubyte
{
	none = 0,
	mod = 1,
	admin = 2
}

struct CommonMessage
{
	string target;
	string sender;
	string message;
	Rank senderRank;
	long senderID;
}
