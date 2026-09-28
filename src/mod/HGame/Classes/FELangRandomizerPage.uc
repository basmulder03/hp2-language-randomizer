//================================================================================
// FELangRandomizerPage.
//
// In-game book page for the language randomizer settings (see
// docs/design.md).
// Reached from FEOptionsPage's language lion button; registered in FEBook
// as "LANGRANDOMIZER". All state lives in LanguagePicker's config vars --
// this page only reads and writes them through LanguagePicker's accessors,
// and every change is saved immediately.
//================================================================================

class FELangRandomizerPage extends baseFEPage;

const MAX_ROWS = 17;
// 9 + 8 rows (16 languages + redub, which is only shown while enabled).
const ROWS_PER_COLUMN = 9;

var HPMenuOptionCheckBox MasterCheck;
var HPMenuOptionCheckBox SkipCheck;
var HPMenuOptionCheckBox MenuCheck;
var HPMenuOptionCheckBox LabelCheck;
var LangMenuButton ModeButton;
var LangMenuButton ResetButton;
var LangMenuButton StatsButton;
var HPMenuOptionCheckBox LangCheck[MAX_ROWS];
var HPMenuOptionHSlider LangSlider[MAX_ROWS];
var HGameLabelControl LangShareLabel[MAX_ROWS];
// LanguagePicker index shown on each row (redub is skipped, so rows and
// language indices diverge).
var int RowLang[MAX_ROWS];
var int NumRows;

var localized string TitleText;
var localized string MasterText;
var localized string SkipText;
var localized string MasterToolText;
var localized string SkipToolText;
var localized string MenuText;
var localized string MenuToolText;
var localized string LabelText;
var localized string LabelToolText;
var localized string ModeText;
var localized string ModeNames[6];
var localized string ModeToolTexts[6];
var localized string WeightToolText;
var localized string ResetText;
var localized string ResetToolText;
var localized string StatsText;

var Color LabelTextColor;
var Color ShareTextColor;

function Created()
{
	local int i, row, col;
	local float colX, rowY;

	CreateTitleButton(TitleText);

	MasterCheck = HPMenuOptionCheckBox(CreateAlignedControl(Class'HPMenuOptionCheckBox', 40.0, 76.0, 260.0, 1.0,,AT_Center));
	MasterCheck.SetText(MasterText);
	MasterCheck.SetFont(0);
	MasterCheck.TextColor = LabelTextColor;

	SkipCheck = HPMenuOptionCheckBox(CreateAlignedControl(Class'HPMenuOptionCheckBox', 330.0, 76.0, 260.0, 1.0,,AT_Center));
	SkipCheck.SetText(SkipText);
	SkipCheck.SetFont(0);
	SkipCheck.TextColor = LabelTextColor;

	MenuCheck = HPMenuOptionCheckBox(CreateAlignedControl(Class'HPMenuOptionCheckBox', 40.0, 96.0, 260.0, 1.0,,AT_Center));
	MenuCheck.SetText(MenuText);
	MenuCheck.SetFont(0);
	MenuCheck.TextColor = LabelTextColor;

	LabelCheck = HPMenuOptionCheckBox(CreateAlignedControl(Class'HPMenuOptionCheckBox', 40.0, 116.0, 260.0, 1.0,,AT_Center));
	LabelCheck.SetText(LabelText);
	LabelCheck.SetFont(0);
	LabelCheck.TextColor = LabelTextColor;

	// Cycles through LanguagePicker's modes (Random, Per character, ...).
	ModeButton = LangMenuButton(CreateAlignedControl(Class'LangMenuButton', 330.0, 92.0, 250.0, 24.0,,AT_Center));
	ModeButton.ButtonWidth = 250.0;
	ModeButton.UpTexture = class'FEInputPage'.default.HoverImage5;
	ModeButton.DownTexture = class'FEInputPage'.default.HoverImage;
	ModeButton.DisabledTexture = class'FEInputPage'.default.HoverImage;
	ModeButton.OverTexture = class'FEInputPage'.default.HoverImage3;
	ModeButton.SetFont(0);
	ModeButton.bAcceptsFocus = false;
	ModeButton.bIgnoreLDoubleClick = true;
	ModeButton.TextColor = ShareTextColor;

	NumRows = 0;
	for (i = 0; i < class'LanguagePicker'.static.GetNumLangs() && NumRows < MAX_ROWS; i++)
	{

		row = NumRows % ROWS_PER_COLUMN;
		col = NumRows / ROWS_PER_COLUMN;
		colX = 40.0 + col * 290.0;
		rowY = 140.0 + row * 31.0;

		RowLang[NumRows] = i;

		LangCheck[NumRows] = HPMenuOptionCheckBox(CreateAlignedControl(Class'HPMenuOptionCheckBox', colX, rowY + 4.0, 115.0, 1.0,,AT_Center));
		LangCheck[NumRows].SetText(class'LanguagePicker'.static.GetLangDisplayName(i));
		LangCheck[NumRows].SetFont(0);
		LangCheck[NumRows].TextColor = LabelTextColor;

		LangSlider[NumRows] = HPMenuOptionHSlider(CreateAlignedControl(Class'HPMenuOptionHSlider', colX + 120.0, rowY, 110.0, 24.0,,AT_Center));
		LangSlider[NumRows].SetRange(0.0, 10.0, 1);
		LangSlider[NumRows].bNoSlidingNotify = True;
		LangSlider[NumRows].SliderWidth = 110;
		LangSlider[NumRows].SetText("");

		LangShareLabel[NumRows] = HGameLabelControl(CreateAlignedControl(Class'HGameLabelControl', colX + 235.0, rowY + 4.0, 45.0, 24.0,,AT_Center));
		LangShareLabel[NumRows].SetFont(0);
		LangShareLabel[NumRows].TextColor = ShareTextColor;

		NumRows++;
	}

	// Same raised-button look as FEInputPage's key buttons.
	ResetButton = LangMenuButton(CreateAlignedControl(Class'LangMenuButton', 40.0, 422.0, 160.0, 24.0,,AT_Center));
	ResetButton.ButtonWidth = 160.0;
	ResetButton.UpTexture = class'FEInputPage'.default.HoverImage5;
	ResetButton.DownTexture = class'FEInputPage'.default.HoverImage;
	ResetButton.DisabledTexture = class'FEInputPage'.default.HoverImage;
	ResetButton.OverTexture = class'FEInputPage'.default.HoverImage3;
	ResetButton.SetFont(0);
	ResetButton.bAcceptsFocus = false;
	ResetButton.bIgnoreLDoubleClick = true;
	ResetButton.TextColor = ShareTextColor;
	ResetButton.SetText(ResetText);

	StatsButton = LangMenuButton(CreateAlignedControl(Class'LangMenuButton', 220.0, 422.0, 160.0, 24.0,,AT_Center));
	StatsButton.ButtonWidth = 160.0;
	StatsButton.UpTexture = ResetButton.UpTexture;
	StatsButton.DownTexture = ResetButton.DownTexture;
	StatsButton.DisabledTexture = ResetButton.DisabledTexture;
	StatsButton.OverTexture = ResetButton.OverTexture;
	StatsButton.SetFont(0);
	StatsButton.bAcceptsFocus = false;
	StatsButton.bIgnoreLDoubleClick = true;
	StatsButton.TextColor = ShareTextColor;
	StatsButton.SetText(StatsText);

	LoadSettings();
	CreateBackPageButton();
	Super.Created();
}

function ShowWindow()
{
	// Settings can also change via ini or the debug console; always show
	// the current state.
	LoadSettings();
	Super.ShowWindow();
}

function LoadSettings()
{
	local int r;

	MasterCheck.bChecked = class'LanguagePicker'.static.IsRandomizerEnabled();
	SkipCheck.bChecked = class'LanguagePicker'.static.IsCutsceneSkipAllowed();
	MenuCheck.bChecked = class'LanguagePicker'.static.IsMenuRandomized();
	LabelCheck.bChecked = class'LanguagePicker'.static.IsLangLabelHidden();
	UpdateModeButton();
	for (r = 0; r < NumRows; r++)
	{
		LangCheck[r].bChecked = class'LanguagePicker'.static.IsLangEnabled(RowLang[r]);
		LangSlider[r].SetValue(class'LanguagePicker'.static.GetLangWeight(RowLang[r]));
		// Redub is a hidden feature: its row only appears once it has been
		// enabled via the "Redub" console command or the ini.
		if (class'LanguagePicker'.static.IsHiddenLang(RowLang[r]))
			ShowRow(r, class'LanguagePicker'.static.IsRedubEnabled());
	}
	UpdateShares();
}

function ShowRow(int r, bool bShow)
{
	if (bShow)
	{
		LangCheck[r].ShowWindow();
		LangSlider[r].ShowWindow();
		LangShareLabel[r].ShowWindow();
	}
	else
	{
		LangCheck[r].HideWindow();
		LangSlider[r].HideWindow();
		LangShareLabel[r].HideWindow();
	}
}

function UpdateModeButton()
{
	ModeButton.SetText(ModeText @ ModeNames[class'LanguagePicker'.static.GetLangMode()]);
}

function UpdateShares()
{
	local int r;
	local float share;

	for (r = 0; r < NumRows; r++)
	{
		share = class'LanguagePicker'.static.GetLangShare(RowLang[r]);
		if (share <= 0.0)
			LangShareLabel[r].SetText("-");
		else if (share < 1.0)
			LangShareLabel[r].SetText("<1%");
		else
			LangShareLabel[r].SetText(string(int(share + 0.5)) $ "%");
	}
}

function Notify (UWindowDialogControl C, byte E)
{
	local int r;
	local bool b;

	Super.Notify(C,E);
	switch (E)
	{
		case DE_Change:
			if (C == MasterCheck)
			{
				b = !class'LanguagePicker'.static.IsRandomizerEnabled();
				class'LanguagePicker'.static.SetRandomizerEnabled(b);
				MasterCheck.bChecked = b;
				UpdateShares();
				return;
			}
			if (C == LabelCheck)
			{
				b = !class'LanguagePicker'.static.IsLangLabelHidden();
				class'LanguagePicker'.static.SetLangLabelHidden(b);
				LabelCheck.bChecked = b;
				return;
			}
			if (C == MenuCheck)
			{
				b = !class'LanguagePicker'.static.IsMenuRandomized();
				class'LanguagePicker'.static.SetMenuRandomized(b);
				MenuCheck.bChecked = b;
				return;
			}
			if (C == SkipCheck)
			{
				b = !class'LanguagePicker'.static.IsCutsceneSkipAllowed();
				class'LanguagePicker'.static.SetCutsceneSkipAllowed(b);
				SkipCheck.bChecked = b;
				return;
			}
			for (r = 0; r < NumRows; r++)
			{
				if (C == LangCheck[r])
				{
					b = !class'LanguagePicker'.static.IsLangEnabled(RowLang[r]);
					class'LanguagePicker'.static.SetLangEnabled(RowLang[r], b);
					LangCheck[r].bChecked = b;
					UpdateShares();
					return;
				}
				if (C == LangSlider[r])
				{
					class'LanguagePicker'.static.SetLangWeight(RowLang[r], LangSlider[r].GetValue());
					UpdateShares();
					return;
				}
			}
			break;
		case DE_Click:
			if (C == ModeButton)
			{
				class'LanguagePicker'.static.SetLangMode(class'LanguagePicker'.static.GetLangMode() + 1);
				UpdateModeButton();
				ToolTip(ModeToolTexts[class'LanguagePicker'.static.GetLangMode()]);
			}
			else if (C == BackPageButton)
				FEBook(book).DoEscapeFromPage();
			else if (C == StatsButton)
				FEBook(book).ChangePageNamed("LANGSTATS");
			else if (C == ResetButton)
			{
				class'LanguagePicker'.static.ResetToDefaults();
				LoadSettings();
			}
			break;
		case DE_MouseEnter:
			if (C == MasterCheck)
				ToolTip(MasterToolText);
			else if (C == SkipCheck)
				ToolTip(SkipToolText);
			else if (C == MenuCheck)
				ToolTip(MenuToolText);
			else if (C == LabelCheck)
				ToolTip(LabelToolText);
			else if (C == ModeButton)
				ToolTip(ModeToolTexts[class'LanguagePicker'.static.GetLangMode()]);
			else if (C == ResetButton)
				ToolTip(ResetToolText);
			else
			{
				for (r = 0; r < NumRows; r++)
				{
					if (C == LangSlider[r])
					{
						ToolTip(WeightToolText);
						break;
					}
				}
			}
			break;
		case DE_MouseLeave:
			ToolTip("");
			break;
	}
}

defaultproperties
{
     TitleText="LANGUAGES"
     MasterText="Randomize dialogue languages"
     SkipText="Allow skipping cutscenes"
     MenuText="Randomize menu text"
     LabelText="Guess the language"
     LabelToolText="The flag and language name appear only near the end of each line: guess by ear first."
     ModeText="Mode:"
     ModeNames(0)="Random"
     ModeNames(1)="Per character"
     ModeNames(2)="Per level"
     ModeNames(3)="Shortest line"
     ModeNames(4)="Longest line"
     ModeNames(5)="Chaos"
     ModeToolTexts(0)="Every line picks a random language (weighted by the sliders)."
     ModeToolTexts(1)="Every character keeps one language for the whole game."
     ModeToolTexts(2)="Every level has its own language."
     ModeToolTexts(3)="Every line plays in whichever enabled language says it fastest."
     ModeToolTexts(4)="Every line plays in whichever enabled language takes longest."
     ModeToolTexts(5)="Audio in one language, subtitles in another. The label shows both."
     MenuToolText="Each menu label in a random language. Takes effect the next time the game starts."
     MasterToolText="Off: every line plays in plain English, without flags or language labels."
     SkipToolText="Off: the skip-cutscene key does nothing."
     ResetText="Reset to defaults"
     StatsText="Statistics"
     ResetToolText="All languages on with equal weights, Random mode; randomizer and menu randomizing on, cutscene skipping off."
     WeightToolText="How often this language is picked, relative to the others. 0 = never."
     LabelTextColor=(R=40,G=180,B=40)
     ShareTextColor=(R=200,G=200,B=200)
}
