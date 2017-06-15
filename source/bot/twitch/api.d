module bot.twitch.api;

import vibe.vibe;

struct TwitchAPI
{
	static Json request(string endpoint, string query = "", HTTPMethod method = HTTPMethod.GET)
	{
		string requestURI = "https://api.twitch.tv/kraken/" ~ endpoint ~ "?client_id=" ~ clientID;
		if (query.length && query[0] == '?')
			query = query[1 .. $];
		if (query.length)
			requestURI ~= "&" ~ query;
		Json ret;
		logInfo("Requesting %s", requestURI);
		requestHTTP(requestURI, (scope req) {
			req.method = method;
			req.headers.addField("Accept", "application/vnd.twitchtv.v5+json");
		}, (scope res) {
			ret = res.readJson();
			if (res.statusCode != HTTPStatus.ok)
			{
				logError("Got error %s while requesting %s. Returned: %s",
					res.statusCode, endpoint ~ '?' ~ query, ret);
				throw new HTTPStatusException(res.statusCode);
			}
		});
		return ret;
	}

	static string clientID;
}
