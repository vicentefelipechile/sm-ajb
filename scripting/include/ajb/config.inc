// =========================================================================================================
// Another Jailbreak — configuration writes that preserve the previous file on failure
// =========================================================================================================

#if defined _ajb_config_included
 #endinput
#endif
#define _ajb_config_included

#include <sourcemod>

#define AJB_CONFIG_LINE_LENGTH 4096

stock KeyValues AJB_Config_Read(const char[] path, const char[] root)
{
	KeyValues kv = new KeyValues(root);
	if (FileExists(path) && !kv.ImportFromFile(path))
	{
		LogError("[AJB] Refusing to overwrite unreadable configuration: %s", path);
		delete kv;
		return null;
	}
	return kv;
}

stock bool AJB_Config_Write(KeyValues kv, const char[] path)
{
	char temporary[PLATFORM_MAX_PATH];
	Format(temporary, sizeof(temporary), "%s.tmp", path);
	kv.Rewind();
	bool saved = kv.ExportToFile(temporary) && RenameFile(path, temporary);
	if (!saved) LogError("[AJB] Could not save configuration: %s", path);
	return saved;
}

stock bool AJB_Config_WriteConVar(const char[] path, const char[] name, const char[] value)
{
	File input = OpenFile(path, "rb");
	if (input == null && FileExists(path))
	{
		LogError("[AJB] Could not read configuration: %s", path);
		return false;
	}

	char temporary[PLATFORM_MAX_PATH];
	Format(temporary, sizeof(temporary), "%s.tmp", path);
	File output = OpenFile(temporary, "wb");
	if (output == null)
	{
		delete input;
		LogError("[AJB] Could not write configuration: %s", temporary);
		return false;
	}

	bool saved = true;
	bool found;
	char line[AJB_CONFIG_LINE_LENGTH], token[128], oldValue[128];
	while (input != null && input.ReadLine(line, sizeof(line)))
	{
		int length = strlen(line);
		if (length == sizeof(line) - 1 && line[length - 1] != '\n')
		{
			saved = false;
			break;
		}
		int offset = BreakString(line, token, sizeof(token));
		if (StrContains(token, "//") != 0 && (StrContains(line, "/*") != -1 || StrContains(line, "*/") != -1))
		{
			saved = false;
			break;
		}
		if (StrEqual(token, name, false))
		{
			int separator = FindCharInString(line, ';');
			int comment = StrContains(line, "//");
			if (offset < 0 || (separator != -1 && (comment == -1 || separator < comment)))
			{
				saved = false;
				break;
			}
			int suffix = BreakString(line[offset], oldValue, sizeof(oldValue));
			if (suffix >= 0)
			{
				offset += suffix;
				TrimString(line[offset]);
				// Refuse compound commands rather than silently removing an owner's other settings.
				if (line[offset] != '\0' && StrContains(line[offset], "//") != 0)
				{
					saved = false;
					break;
				}
			}
			else line[offset] = '\0';
			saved = output.WriteLine("%s \"%s\" %s", name, value, line[offset]);
			found = true;
		}
		else saved = output.WriteString(line, false);
		if (!saved) break;
	}
	if (input != null && input.Position != input.Size()) saved = false;
	if (saved && !found) saved = output.WriteLine("\n%s \"%s\"", name, value);
	if (!output.Flush()) saved = false;
	delete input;
	delete output;
	if (saved) saved = RenameFile(path, temporary);
	if (!saved) LogError("[AJB] Could not safely update %s in %s", name, path);
	return saved;
}
