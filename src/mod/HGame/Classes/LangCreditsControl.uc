//================================================================================
// LangCreditsControl.
//
// Credits roll for the language randomizer (see docs/design.md).
// FECreditsPage creates this instead of the stock HPCreditsControl. The roll
// is built once per showing:
//   1. an overview of the languages heard this run (harry's LangStat*
//      counts), when there is a run with any lines played;
//   2. the stock credits (HPCredits.int Line0.. up to its /Q);
//   3. each dubbed language's own localization team and voice cast, from
//      LangCredits.dat (tools/scripts/generate_lang_credits.py).
// Painting is the stock HPCreditsControl.Paint, reading from that list and
// switching to the native font for Cyrillic (rus) lines.
//================================================================================

class LangCreditsControl extends HPCreditsControl;

var array<string> CreditLines;
var array<string> CreditLangs;
var array<string> RawLangCredits;
var bool bBuilt;

var localized string OverviewTitle;
var localized string TotalText;
var localized string CastsTitle;

function Reset()
{
	Super.Reset();
	bBuilt = False;
}

function AddLine(string Lang, string S)
{
	CreditLines[CreditLines.Length] = S;
	CreditLangs[CreditLangs.Length] = Lang;
}

function AddOverview()
{
	local harry H;
	local int i, j, r, n, total, best, tmp;
	local int Counts[17];
	local int Order[17];

	H = harry(GetPlayerOwner());
	if (H == None)
		return;
	n = Min(class'LanguagePicker'.static.GetNumLangs(), 17);
	for (i = 0; i < n; i++)
	{
		for (r = 0; r < H.LangStatNumRows(0); r++)
			Counts[i] += H.LangStatGet(0, r, i);
		total += Counts[i];
		Order[i] = i;
	}
	if (total <= 0)
		return;

	// Most-heard first.
	for (i = 0; i < n - 1; i++)
	{
		best = i;
		for (j = i + 1; j < n; j++)
			if (Counts[Order[j]] > Counts[Order[best]])
				best = j;
		tmp = Order[i]; Order[i] = Order[best]; Order[best] = tmp;
	}

	AddLine("", "/b" $ OverviewTitle);
	AddLine("", TotalText @ string(total));
	AddLine("", "");
	for (i = 0; i < n; i++)
	{
		if (Counts[Order[i]] <= 0)
			break;
		AddLine("", class'LanguagePicker'.static.GetLangDisplayName(Order[i]) $ " - " $ string(Counts[Order[i]])
			$ " (" $ string(int(100.0 * Counts[Order[i]] / total + 0.5)) $ "%, "
			$ class'LanguagePicker'.static.FormatSeconds(H.LangStatSeconds[Order[i]]) $ ")");
	}
	AddLine("", "");
	AddLine("", "");
}

function AddStockCredits()
{
	local int idx;
	local string S;

	for (idx = 0; idx < 2000; idx++)
	{
		S = Localize("all", "Line" $ idx, "HPCredits");
		if (Left(S, 2) ~= "/Q" || Left(S, 2) == "<?")
			break;
		AddLine("", S);
	}
}

function AddLangCredits()
{
	local int i, p, li;
	local string Lang, S, PrevLang;

	RawLangCredits.Length = 0;
	LoadStringArray(RawLangCredits, "LangCredits.dat");
	if (RawLangCredits.Length == 0)
		return;

	AddLine("", "");
	AddLine("", "/b" $ CastsTitle);
	AddLine("", "");
	for (i = 0; i < RawLangCredits.Length; i++)
	{
		p = InStr(RawLangCredits[i], "|");
		if (p < 0)
			continue;
		Lang = Left(RawLangCredits[i], p);
		S = Mid(RawLangCredits[i], p + 1);
		if (Lang != PrevLang)
		{
			// Section title: the language's name as used on the settings page.
			li = class'LanguagePicker'.static.GetLangIndex(Lang);
			if (li >= 0)
			{
				AddLine("", "");
				AddLine("", "/b~ " $ class'LanguagePicker'.static.GetLangDisplayName(li) $ " ~");
			}
			PrevLang = Lang;
		}
		AddLine(Lang, S);
	}
}

function Build()
{
	CreditLines.Length = 0;
	CreditLangs.Length = 0;
	AddOverview();
	AddStockCredits();
	AddLangCredits();
	AddLine("", "/Q");
	bBuilt = True;
}

function Paint (Canvas C, float MouseX, float MouseY)
{
	local float LineWidth;
	local float LineHeight;
	local float Y;
	local float YDelta;
	local int idx;
	local bool bDone;
	local string S;
	local Font NativeFont;

	if ( !bBuilt )
		Build();
	if ( _StartTime < 0.0 )
	{
		_StartTime = GetLevel().TimeSeconds;
		_FirstVisibleCreditIdx = 0;
		_FirstVisibleCreditYDelta = 0.0;
	}
	C.DrawColor = TextColor;
	Y = WinHeight - (GetLevel().TimeSeconds - _StartTime) * 30.0;
	YDelta = _FirstVisibleCreditYDelta;
	idx = _FirstVisibleCreditIdx;
	bDone = False;
	while ( !bDone )
	{
		C.Font = Root.Fonts[2];
		if ( idx < CreditLines.Length )
			S = CreditLines[idx];
		else
			S = "/Q";
		if ( Left(S,1) == "/" )
		{
			if ( Mid(S,1,1) ~= "Q" )
			{
				bDone = True;
				S = "";
			}
			else if ( Mid(S,1,1) ~= "B" )
			{
				C.Font = Root.Fonts[3];
				S = Mid(S,2);
			}
		}
		// Cyrillic needs the native font; the stock menu fonts have no glyphs.
		if ( S != "" && idx < CreditLangs.Length && CreditLangs[idx] == "rus" )
		{
			NativeFont = class'LanguagePicker'.static.GetFontForLanguage("rus", Root.Console);
			if ( NativeFont != None )
				C.Font = NativeFont;
		}
		if ( S != "" )
		{
			TextSize(C,S,LineWidth,LineHeight);
			ClipText(C,(WinWidth - LineWidth) / 2,Y + YDelta,S);
		}
		else
		{
			TextSize(C,"A",LineWidth,LineHeight);
		}
		YDelta += LineHeight;
		idx++;
		if ( Y + YDelta < 0.0 )
		{
			_FirstVisibleCreditIdx = idx;
			_FirstVisibleCreditYDelta = YDelta;
		}
		if ( Y + YDelta > WinHeight )
		{
			bDone = True;
		}
	}
	if ( Y + YDelta < 0.0 )
	{
		_StartTime = -1.0;
	}
}

defaultproperties
{
     OverviewTitle="Languages heard this run"
     TotalText="Voice lines played:"
     CastsTitle="Voices from around the world"
}
