options = {
	["miscellaneous"] = {
		["autologin"] = true,
		["collect_stat"] = false,
		["launcher"] = false,
	},
	["plugins"] = {
		["Tacview"] = {
			-- relative tacviewExportPath supported since 1.9.5 beta 15
			-- TODO: use relative path when released as stable version
			-- https://www.tacview.net/download/beta/en/
			-- https://forum.dcs.world/topic/116593-tacview-the-acmi-for-dcs-world-official-thread/page/77/#findComment-5696840
			-- http://dogsofwarvu.com/forum/index.php/topic,9832.0.html?PHPSESSID=d4q7nh84g7nk9j3fvr66kbkkqe
			["tacviewExportPath"] = "C:\\DCS_configs\\Tacview",
			["tacviewFlightDataRecordingEnabled"] = true,
			["tacviewModuleEnabled"] = true,
			["tacviewMultiplayerFlightsAsHost"] = 2,
			["tacviewPlaybackDelay"] = 600,
			["tacviewRealTimeTelemetryEnabled"] = false,
			["tacviewRealTimeTelemetryPassword"] = "",
			["tacviewRealTimeTelemetryPort"] = "42674",
			["tacviewRemoteControlEnabled"] = false,
			["tacviewRemoteControlPassword"] = "",
			["tacviewRemoteControlPort"] = "42675",
		},
	},
}
