//================================================================================
// FELangStatsPage.
//
// Run statistics for the language randomizer (see docs/design.md):
// how often each language was used this run, overall and split by line
// type, character and level. Reached from FELangRandomizerPage's
// "Statistics" button; registered in FEBook as "LANGSTATS". Reads the
// counts from harry's LangStat* accessors (filled by
// LanguagePicker.RecordLine).
//================================================================================

class FELangStatsPage extends baseFEPage;

// Row spacing matches FELangRandomizerPage (36 units): tighter rows let
// the menu font overlap at non-native window sizes (e.g. 1600x900).
const ROWS = 8;
const MAX_ITEMS = 128;
const NUM_MODES = 4;
const MODE_LANGUAGE = 0;
const MODE_LINETYPE = 1;
const MODE_SPEAKER = 2;
const MODE_LEVEL = 3;
const NUM_SPEAKER_NAMES = 40;

var LangMenuButton ModeButton[NUM_MODES];
var LangMenuButton PrevButton;
var LangMenuButton NextButton;
var LangMenuButton CreditsButton;
var HGameLabelControl PageLabel;
var HGameLabelControl SummaryLabel;
var HGameLabelControl NameLabel[ROWS];
var HGameLabelControl CountLabel[ROWS];
var HGameLabelControl DetailLabel[ROWS];

var int Mode;
var int PageIdx;
var int NumItems;
var string ItemName[MAX_ITEMS];
var int ItemCount[MAX_ITEMS];
var string ItemDetail[MAX_ITEMS];

var localized string TitleText;
var localized string ModeText[NUM_MODES];
var localized string LineTypeText[5];
var localized string PrevText;
var localized string NextText;
var localized string TotalText;
var localized string NoDataText;
var localized string PageText;
var localized string OtherText;
var localized string CreditsText;
var string SpeakerCodes[NUM_SPEAKER_NAMES];
var localized string SpeakerNames[NUM_SPEAKER_NAMES];

var Color LabelTextColor;
var Color ValueTextColor;
var Color SelectedTextColor;

function LangMenuButton MakeButton(float X, float Y, float W, string Text)
{
	local LangMenuButton B;

	// Same raised-button look as FEInputPage's key buttons.
	B = LangMenuButton(CreateAlignedControl(Class'LangMenuButton', X, Y, W, 24.0,,AT_Center));
	B.ButtonWidth = W;
	B.Align = TA_Center;
	B.UpTexture = class'FEInputPage'.default.HoverImage5;
	B.DownTexture = class'FEInputPage'.default.HoverImage;
	B.DisabledTexture = class'FEInputPage'.default.HoverImage;
	B.OverTexture = class'FEInputPage'.default.HoverImage3;
	B.SetFont(0);
	B.bAcceptsFocus = false;
	B.bIgnoreLDoubleClick = true;
	B.TextColor = ValueTextColor;
	B.SetText(Text);
	return B;
}

function HGameLabelControl MakeLabel(float X, float Y, float W, Color C)
{
	local HGameLabelControl L;

	L = HGameLabelControl(CreateAlignedControl(Class'HGameLabelControl', X, Y, W, 20.0,,AT_Center));
	L.SetFont(0);
	L.TextColor = C;
	return L;
}

function Created()
{
	local int i;

	CreateTitleButton(TitleText);

	for (i = 0; i < NUM_MODES; i++)
		ModeButton[i] = MakeButton(40.0 + i * 145.0, 80.0, 135.0, ModeText[i]);

	for (i = 0; i < ROWS; i++)
	{
		NameLabel[i] = MakeLabel(40.0, 120.0 + i * 36.0, 180.0, LabelTextColor);
		CountLabel[i] = MakeLabel(225.0, 120.0 + i * 36.0, 60.0, ValueTextColor);
		DetailLabel[i] = MakeLabel(290.0, 120.0 + i * 36.0, 310.0, ValueTextColor);
	}

	// LangMenuButton draws ~180 units wide whatever W is passed (its
	// texture sets the size), so the pager is laid out for that width.
	SummaryLabel = MakeLabel(40.0, 396.0, 400.0, LabelTextColor);
	PrevButton = MakeButton(40.0, 422.0, 120.0, PrevText);
	NextButton = MakeButton(170.0, 422.0, 120.0, NextText);
	PageLabel = MakeLabel(300.0, 426.0, 140.0, ValueTextColor);
	// The credits otherwise only roll at the end of the game (or from a
	// debug-mode button); they open with this run's language overview.
	CreditsButton = MakeButton(450.0, 422.0, 120.0, CreditsText);

	CreateBackPageButton();
	Super.Created();
}

function ShowWindow()
{
	Rebuild();
	Super.ShowWindow();
}

// --- data -----------------------------------------------------------------

function string Percent(int Part, int Whole)
{
	if (Whole <= 0)
		return "0%";
	if (Part * 100 < Whole)
		return "<1%";
	return string(int(100.0 * Part / Whole + 0.5)) $ "%";
}

function string SpeakerDisplayName(string Code)
{
	local int i;

	if (Code == "OTHER")
		return OtherText;
	for (i = 0; i < NUM_SPEAKER_NAMES; i++)
		if (SpeakerCodes[i] != "" && SpeakerCodes[i] ~= Code)
			return SpeakerNames[i];
	return Code;
}

// "Deutsch 45%, Polski 30%" for one table row (top two, to keep the row
// short enough for small window sizes).
function string TopLanguages(harry H, int Table, int Row, int RowTotal)
{
	local int k, l, best, bestCount, n;
	local int used[17];
	local string s;

	for (k = 0; k < 2; k++)
	{
		best = -1;
		bestCount = 0;
		n = class'LanguagePicker'.static.GetNumLangs();
		for (l = 0; l < n; l++)
		{
			if (used[l] == 0 && H.LangStatGet(Table, Row, l) > bestCount)
			{
				best = l;
				bestCount = H.LangStatGet(Table, Row, l);
			}
		}
		if (best < 0)
			break;
		used[best] = 1;
		if (s != "")
			s = s $ ", ";
		s = s $ class'LanguagePicker'.static.GetLangDisplayName(best) @ Percent(bestCount, RowTotal);
	}
	return s;
}

function AddItem(string Name, int Count, string Detail)
{
	if (NumItems >= MAX_ITEMS || Count <= 0)
		return;
	ItemName[NumItems] = Name;
	ItemCount[NumItems] = Count;
	ItemDetail[NumItems] = Detail;
	NumItems++;
}

function SortItemsByCount()
{
	local int i, j, best, c;
	local string s;

	for (i = 0; i < NumItems - 1; i++)
	{
		best = i;
		for (j = i + 1; j < NumItems; j++)
			if (ItemCount[j] > ItemCount[best])
				best = j;
		if (best != i)
		{
			s = ItemName[i]; ItemName[i] = ItemName[best]; ItemName[best] = s;
			s = ItemDetail[i]; ItemDetail[i] = ItemDetail[best]; ItemDetail[best] = s;
			c = ItemCount[i]; ItemCount[i] = ItemCount[best]; ItemCount[best] = c;
		}
	}
}

function int LangTotal(harry H, int Lang)
{
	local int r, t;

	for (r = 0; r < H.LangStatNumRows(0); r++)
		t += H.LangStatGet(0, r, Lang);
	return t;
}

function int SumRow(harry H, int Table, int Row)
{
	local int l, t;

	for (l = 0; l < class'LanguagePicker'.static.GetNumLangs(); l++)
		t += H.LangStatGet(Table, Row, l);
	return t;
}

function Rebuild()
{
	local harry H;
	local int i, n, total, rowTotal, table;
	local string key, name;

	NumItems = 0;
	PageIdx = 0;
	H = harry(GetPlayerOwner());
	if (H != None)
	{
		n = class'LanguagePicker'.static.GetNumLangs();
		for (i = 0; i < n; i++)
			total += LangTotal(H, i);

		if (Mode == MODE_LANGUAGE)
		{
			for (i = 0; i < n; i++)
				AddItem(class'LanguagePicker'.static.GetLangDisplayName(i), LangTotal(H, i),
					Percent(LangTotal(H, i), total) $ "   " $ class'LanguagePicker'.static.FormatSeconds(H.LangStatSeconds[i]));
		}
		else
		{
			if (Mode == MODE_LINETYPE)
				table = 0;
			else if (Mode == MODE_SPEAKER)
				table = 1;
			else
				table = 2;
			for (i = 0; i < H.LangStatNumRows(table); i++)
			{
				key = H.LangStatKey(table, i);
				if (table == 0)
					name = LineTypeText[i];
				else if (key == "")
					continue;
				else if (table == 1)
					name = SpeakerDisplayName(key);
				else if (key == "OTHER")
					name = OtherText;
				else
					name = key;
				rowTotal = SumRow(H, table, i);
				AddItem(name, rowTotal, TopLanguages(H, table, i, rowTotal));
			}
		}
		SortItemsByCount();
	}

	if (total > 0)
		SummaryLabel.SetText(TotalText @ string(total));
	else
		SummaryLabel.SetText(NoDataText);
	Refresh();
}

function int NumPages()
{
	return Max(1, (NumItems + ROWS - 1) / ROWS);
}

function Refresh()
{
	local int r, i;

	for (i = 0; i < NUM_MODES; i++)
	{
		if (i == Mode)
			ModeButton[i].TextColor = SelectedTextColor;
		else
			ModeButton[i].TextColor = ValueTextColor;
	}
	for (r = 0; r < ROWS; r++)
	{
		i = PageIdx * ROWS + r;
		if (i < NumItems)
		{
			NameLabel[r].SetText(ItemName[i]);
			CountLabel[r].SetText(string(ItemCount[i]));
			DetailLabel[r].SetText(ItemDetail[i]);
		}
		else
		{
			NameLabel[r].SetText("");
			CountLabel[r].SetText("");
			DetailLabel[r].SetText("");
		}
	}
	PageLabel.SetText(PageText @ string(PageIdx + 1) $ "/" $ string(NumPages()));
}

// --- input ----------------------------------------------------------------

function Notify (UWindowDialogControl C, byte E)
{
	local int i;

	Super.Notify(C,E);
	if (E != DE_Click)
		return;

	if (C == BackPageButton)
	{
		FEBook(book).DoEscapeFromPage();
		return;
	}
	if (C == CreditsButton)
	{
		FEBook(book).ChangePageNamed("CREDITSPAGE");
		return;
	}
	if (C == PrevButton)
	{
		if (PageIdx > 0)
			PageIdx--;
		Refresh();
		return;
	}
	if (C == NextButton)
	{
		if (PageIdx < NumPages() - 1)
			PageIdx++;
		Refresh();
		return;
	}
	for (i = 0; i < NUM_MODES; i++)
	{
		if (C == ModeButton[i])
		{
			Mode = i;
			Rebuild();
			return;
		}
	}
}

defaultproperties
{
     TitleText="LANGUAGE STATISTICS"
     ModeText(0)="By language"
     ModeText(1)="By line type"
     ModeText(2)="By character"
     ModeText(3)="By level"
     LineTypeText(0)="Dialogue"
     LineTypeText(1)="Cutscenes"
     LineTypeText(2)="NPC chatter"
     LineTypeText(3)="Position triggers"
     LineTypeText(4)="Spells"
     PrevText="< Previous"
     NextText="Next >"
     TotalText="Lines this run:"
     NoDataText="No lines played yet this run."
     PageText="Page"
     OtherText="Other"
     CreditsText="Credits"
     SpeakerCodes(0)="HRY"
     SpeakerNames(0)="Harry"
     SpeakerCodes(1)="RON"
     SpeakerNames(1)="Ron"
     SpeakerCodes(2)="HER"
     SpeakerNames(2)="Hermione"
     SpeakerCodes(3)="NAR"
     SpeakerNames(3)="Narrator"
     SpeakerCodes(4)="DOB"
     SpeakerNames(4)="Dobby"
     SpeakerCodes(5)="DUM"
     SpeakerNames(5)="Dumbledore"
     SpeakerCodes(6)="GIL"
     SpeakerNames(6)="Lockhart"
     SpeakerCodes(7)="SNP"
     SpeakerNames(7)="Snape"
     SpeakerCodes(8)="MCG"
     SpeakerNames(8)="McGonagall"
     SpeakerCodes(9)="FLT"
     SpeakerNames(9)="Flitwick"
     SpeakerCodes(10)="SPR"
     SpeakerNames(10)="Sprout"
     SpeakerCodes(11)="DRC"
     SpeakerNames(11)="Draco"
     SpeakerCodes(12)="GIN"
     SpeakerNames(12)="Ginny"
     SpeakerCodes(13)="LUC"
     SpeakerNames(13)="Lucius Malfoy"
     SpeakerCodes(14)="MYR"
     SpeakerNames(14)="Moaning Myrtle"
     SpeakerCodes(15)="NHN"
     SpeakerNames(15)="Nearly Headless Nick"
     SpeakerCodes(16)="FIL"
     SpeakerNames(16)="Filch"
     SpeakerCodes(17)="ARA"
     SpeakerNames(17)="Aragog"
     SpeakerCodes(18)="TMR"
     SpeakerNames(18)="Tom Riddle"
     SpeakerCodes(19)="PVS"
     SpeakerNames(19)="Peeves"
     SpeakerCodes(20)="LEE"
     SpeakerNames(20)="Lee Jordan"
     SpeakerCodes(21)="OWD"
     SpeakerNames(21)="Oliver Wood"
     SpeakerCodes(22)="FRD"
     SpeakerNames(22)="Fred"
     SpeakerCodes(23)="GRG"
     SpeakerNames(23)="George"
     SpeakerCodes(24)="PCY"
     SpeakerNames(24)="Percy"
     SpeakerCodes(25)="ASG"
     SpeakerNames(25)="Harry (as Goyle)"
     SpeakerCodes(26)="GOY"
     SpeakerNames(26)="Goyle"
     SpeakerCodes(27)="BAS"
     SpeakerNames(27)="Basilisk"
     SpeakerCodes(28)="SOH"
     SpeakerNames(28)="Sorting Hat"
     SpeakerCodes(29)="POM"
     SpeakerNames(29)="Madam Pomfrey"
     SpeakerCodes(30)="FAT"
     SpeakerNames(30)="Fat Friar"
     SpeakerCodes(31)="YHA"
     SpeakerNames(31)="Young Hagrid"
     SpeakerCodes(32)="HDW"
     SpeakerNames(32)="Hagrid"
     SpeakerCodes(33)="GRM"
     SpeakerNames(33)="Gryffindor student"
     SpeakerCodes(34)="VOL"
     SpeakerNames(34)="Voldemort"
     SpeakerCodes(35)="FLD"
     SpeakerNames(35)="Fat Lady"
     SpeakerCodes(36)="GRF"
     SpeakerNames(36)="Gryffindor student"
     SpeakerCodes(37)="EMO"
     SpeakerNames(37)="Crowd"
     SpeakerCodes(38)="SPI"
     SpeakerNames(38)="Spiders"
     LabelTextColor=(R=40,G=180,B=40)
     ValueTextColor=(R=200,G=200,B=200)
     SelectedTextColor=(R=255,G=215,B=0)
}
