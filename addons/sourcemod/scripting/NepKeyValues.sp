public KeyValues InitializeKV(const char[] path, const char[] keyname)
{
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), path);
	KeyValues kv = new KeyValues(keyname);
	kv.SetEscapeSequences(true);
	kv.ImportFromFile(sPath);
	return kv;
}

public ArrayList ToArrayList_MatchBySectionName(KeyValues kv, const char[] sectionname,const char [] keyname)
{
    kv.GotoFirstSubKey();
    ArrayList buffer = new ArrayList(100);
    char keynamebuffer[100][128];
    ExplodeString(keyname,",",keynamebuffer,100,128);
    do
    {
        char sectionnamebuffer[128];
        kv.GetSectionName(sectionnamebuffer, sizeof(sectionnamebuffer));
        if(StrEqual(sectionname,sectionnamebuffer))
        {   
            for(int i = 0; i < 100; i++)
            {                
               if(!StrEqual(keynamebuffer[i],""))
               {
                    char keyvaluebuffer[128];
                    kv.GetString(keynamebuffer[i],keyvaluebuffer,sizeof(keyvaluebuffer));
                    buffer.PushString(keyvaluebuffer);
               }
            }
        }
    }
    while (kv.GotoNextKey());
    return buffer;
}

public int GetSectionCounts(KeyValues kv)
{
    int i = 0;
    kv.GotoFirstSubKey();
    while(kv.GotoNextKey())
    {
        i++;
    }
    return i;
}