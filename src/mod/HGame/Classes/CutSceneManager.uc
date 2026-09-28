//================================================================================
// CutSceneManager.
//================================================================================
// Omega: Black bars use DeltaTime now

class CutSceneManager extends HudItemManager;

const SLIDE_DIVISOR= 15;
var Texture textureBorder;
var float fCurrBorderHeight;

// Omega: max border height
var float fMaxBorderHeight;

var float fBorderMoveTime;

var bool bResetBorderHeightToMax;
var string strText;
var string strCutCommentText;
var bool bBothBordersActive;
var bool bPopupBorderActive;
var Color colorCutTextBlue;
var bool bShowFF;
var Texture textureFFIcons[3];
var int curFFIcon;

// The line's language and ID, captured once at SetText time. DrawText must
// not re-read LanguagePicker's "last resolved" state every frame: another
// line may have been resolved since, and the subtitle would show its flag.
var string strLineLang;
var string strLineDialogID;
// Chaos mode's audio language (== strLineLang otherwise), and when/how long
// the line shows -- for the guess-the-language reveal.
var string strLineAudioLang;
var float fLineStartTime;
var float fLineDuration;
// Wrapped subtitle lines (DrawWrappedSubtitle); static array because
// UnrealScript can't pass one as an out parameter.
var string WrapLines[8];

function StartCutScene ()
{
	if (  !IsInState('SlideIn') &&  !IsInState('Hold') )
	{
		GotoState('SlideIn');
	}
}

function EndCutScene ()
{
	//cm(Self$ ".EndCutScene() called");
	strCutCommentText = "";
	if (  !IsInState('SlideOut') &&  !IsInState('Idle') )
	{
		GotoState('SlideOut');
	}
}

function SetText (string strSetText, float fSetTextDuration)
{
	SetTimer(0.0,False);
	strText = strSetText;
	// Capture LanguagePicker's shared "last resolved" state right here,
	// atomically with strText -- this is the ONE moment we know for
	// certain which language strText actually came from. DrawText must
	// never re-query the global itself; by the time DrawText runs on a
	// later frame, some other unrelated line may have already overwritten
	// it.
	strLineLang = class'LanguagePicker'.static.GetLastResolvedLang();
	strLineDialogID = class'LanguagePicker'.static.GetLastResolvedDialogID();
	strLineAudioLang = class'LanguagePicker'.static.GetLastResolvedAudioLang();
	fLineStartTime = Level.TimeSeconds;
	fLineDuration = fSetTextDuration;
	if ( fSetTextDuration > 0 )
	{
		SetTimer(fSetTextDuration,False);
	}
	StartCutScene();
}

function ClearText ()
{
	strText = "";
	strCutCommentText = "";
	if (  !Level.PlayerHarryActor.bIsCaptured )
	{
		EndCutScene();
	}
}

function SetCutCommentText (string strText)
{
  	strCutCommentText = strText;
}

event Timer ()
{
	strText = "";
	if (  !Level.PlayerHarryActor.bIsCaptured )
	{
		EndCutScene();
	}
}

function DrawBorder (Canvas Canvas)
{
	if ( Level.PlayerHarryActor.bIsCaptured )
	{
		Canvas.SetPos(0.0,0.0);
		// Metallicafan212:	Fuck it, prevent AA issues
		Canvas.DrawTile(textureBorder, Canvas.SizeX + 1, fCurrBorderHeight, 0.0, 0.0, textureBorder.USize, textureBorder.VSize);
	}
	Canvas.SetPos(0.0, Canvas.SizeY - fCurrBorderHeight);
	// Metallicafan212:	Same here
	Canvas.DrawTile(textureBorder, Canvas.SizeX + 1, fCurrBorderHeight + 1, 0.0, 0.0, textureBorder.USize, textureBorder.VSize);
}

function SetCurrBorderHeight (Canvas Canvas)
{
}

function float GetMaxBorderHeight (Canvas Canvas)
{
  	return GetMaxBorderHeightFromCanvasHeight(Canvas.SizeY);
}

function float GetMaxBorderHeightFromCanvasHeight (int nCanvasSizeY)
{
  	return nCanvasSizeY / 8.0;
}

// "Guess the language" setting: the flag and language name stay hidden for
// the first 60% of the line, then appear so the guess can be checked. Lines
// shown without a known duration stay hidden.
function bool IsLabelHiddenNow()
{
	if ( !class'LanguagePicker'.static.IsLangLabelHidden() )
		return False;
	if ( fLineDuration <= 0 )
		return True;
	return Level.TimeSeconds - fLineStartTime < fLineDuration * 0.6;
}

// Word-wraps S to MaxW into WrapLines; a word wider than a whole line
// (e.g. Japanese, which has no spaces) is broken between characters.
// Returns the line count (at most 8; any rest goes on the last line).
function int WrapSubtitle (Canvas Canvas, string S, float MaxW)
{
	local int n, p, i;
	local string Word, Cur, Test, Piece, C;
	local float W, H;

	for ( i = 0; i < ArrayCount(WrapLines); i++ )
		WrapLines[i] = "";
	n = 0;
	Cur = "";
	while ( S != "" )
	{
		p = InStr(S, " ");
		if ( p < 0 )
		{
			Word = S;
			S = "";
		}
		else
		{
			Word = Left(S, p);
			S = Mid(S, p + 1);
		}
		if ( Word == "" )
			continue;
		if ( Cur == "" )
			Test = Word;
		else
			Test = Cur $ " " $ Word;
		Canvas.TextSize(Test, W, H);
		if ( W <= MaxW )
		{
			Cur = Test;
			continue;
		}
		if ( Cur != "" && n < ArrayCount(WrapLines) - 1 )
		{
			WrapLines[n++] = Cur;
			Cur = "";
		}
		else if ( Cur != "" )
		{
			Cur = Cur $ " ";
		}
		// Word alone: break it between characters if it doesn't fit.
		Canvas.TextSize(Cur $ Word, W, H);
		if ( W <= MaxW )
		{
			Cur = Cur $ Word;
			continue;
		}
		Piece = Cur;
		for ( i = 0; i < Len(Word); i++ )
		{
			C = Mid(Word, i, 1);
			Canvas.TextSize(Piece $ C, W, H);
			if ( W > MaxW && Piece != "" && n < ArrayCount(WrapLines) - 1 )
			{
				WrapLines[n++] = Piece;
				Piece = C;
			}
			else
			{
				Piece = Piece $ C;
			}
		}
		Cur = Piece;
	}
	if ( Cur != "" )
		WrapLines[n++] = Cur;
	return n;
}

// Randomized subtitles: wrapped into the area right of the flag and each
// line centered there. Font falls back Med -> Small -> Tiny until it fits
// the subtitle bar, like the stock DrawCutStyleText; native-script lines
// (jap/rus) keep their one native font.
function DrawWrappedSubtitle (Canvas Canvas, string S, float LeftX, float Y, float AvailH, Font NativeFont)
{
	local baseConsole Con;
	local Font Fonts[3];
	local int nFonts, f, i, NumLines;
	local float AreaW, W, H;
	local Font fontSave;
	local Color colorSave;
	local byte styleSave;

	if ( S == "" )
		return;
	AreaW = Canvas.SizeX - 8 - LeftX;
	if ( NativeFont != None )
	{
		Fonts[0] = NativeFont;
		nFonts = 1;
	}
	else
	{
		Con = baseConsole(Level.PlayerHarryActor.Player.Console);
		Fonts[0] = Con.LocalMedFont;
		Fonts[1] = Con.LocalSmallFont;
		Fonts[2] = Con.LocalTinyFont;
		nFonts = 3;
	}

	fontSave = Canvas.Font;
	colorSave = Canvas.DrawColor;
	styleSave = Canvas.Style;
	for ( f = 0; f < nFonts; f++ )
	{
		Canvas.Font = Fonts[f];
		NumLines = WrapSubtitle(Canvas, S, AreaW);
		Canvas.TextSize("A", W, H);
		if ( NumLines * H <= AvailH )
			break;
	}
	Canvas.Style = 2;
	Canvas.DrawColor = colorCutTextBlue;
	for ( i = 0; i < NumLines; i++ )
	{
		Canvas.TextSize(WrapLines[i], W, H);
		Canvas.SetPos(LeftX + (AreaW - W) / 2, Y + i * H);
		Canvas.DrawText(WrapLines[i], False);
	}
	Canvas.Font = fontSave;
	Canvas.DrawColor = colorSave;
	Canvas.Style = styleSave;
}

function DrawText (Canvas Canvas)
{
	local string CurrentLang;
	local string CurrentDialogID;
	local string strComposedText;
	local string NativeText;
	local Texture FlagTex;
	local Font NativeFont;
	local int nTextXPos;

	nTextXPos = 0;
	strComposedText = strText;
	// Randomizer off: stock subtitle, no flag/label/native font.
	if ( strText != "" && class'LanguagePicker'.static.IsRandomizerEnabled() )
	{
		CurrentLang = strLineLang;
		CurrentDialogID = strLineDialogID;
		// Japanese and Russian have their own UTF-16 text source (the merged
		// .int files are cp1252); NativeText is "" for other languages.
		NativeText = class'LanguagePicker'.static.GetNativeText(CurrentDialogID, CurrentLang);
		if ( NativeText != "" )
		{
			strComposedText = NativeText;
		}
		if ( !IsLabelHiddenNow() )
		{
			strComposedText = class'LanguagePicker'.static.ComposeSubtitle(CurrentLang, strComposedText, strLineAudioLang);
		}
		// None for every language except jap -- DrawCutStyleText treats a
		// None fontText exactly like the pre-Task-8 call (its own
		// LocalMedFont default), so this is a no-op for the other 13
		// languages.
		NativeFont = class'LanguagePicker'.static.GetFontForLanguage(CurrentLang, Level.PlayerHarryActor.Player.Console);
		if ( !IsLabelHiddenNow() )
		{
			FlagTex = class'LanguagePicker'.static.GetFlagTexture(CurrentLang);
		}
		if ( FlagTex != None )
		{
			Canvas.SetPos(0, Canvas.SizeY - fCurrBorderHeight + 1);
			Canvas.DrawIcon(FlagTex, 1.0);
			// HPHud.DrawCutStyleText's centering formula computes an
			// absolute draw X as (Canvas.SizeX - fTextW - nXPos) / 2, i.e.
			// it SUBTRACTS nXPos before halving. A positive nXPos here
			// would therefore shift the drawn text LEFT (toward the icon,
			// wrong direction) by nXPos/2. To shift the drawn text RIGHT
			// by D pixels (clearing the icon), nXPos must be -2*D.
			nTextXPos = -2 * (FlagTex.USize + 4);
		}
	}
	if ( strText != "" && class'LanguagePicker'.static.IsRandomizerEnabled() )
	{
		// Own layout: the stock DrawCutStyleText treats the flag offset as an
		// absolute start for lines wider than the screen, so long lines ran
		// over the flag and off the edge.
		if ( FlagTex != None )
			DrawWrappedSubtitle(Canvas, strComposedText, FlagTex.USize + 8, Canvas.SizeY - fCurrBorderHeight + 1, GetMaxBorderHeight(Canvas), NativeFont);
		else
			DrawWrappedSubtitle(Canvas, strComposedText, 8, Canvas.SizeY - fCurrBorderHeight + 1, GetMaxBorderHeight(Canvas), NativeFont);
	}
	else
	{
		HPHud(Level.PlayerHarryActor.myHUD).DrawCutStyleText(Canvas,strComposedText,nTextXPos,Canvas.SizeY - fCurrBorderHeight + 1,GetMaxBorderHeight(Canvas),colorCutTextBlue,NativeFont);
	}
	if ( strCutCommentText != "" )
	{
		HPHud(Level.PlayerHarryActor.myHUD).DrawCutStyleText(Canvas,strCutCommentText,0,5,GetMaxBorderHeight(Canvas),colorCutTextBlue);
	}
	if ( bShowFF )
	{
		if ( textureFFIcons[0] == None )
		{
			textureFFIcons[0] = Texture(DynamicLoadObject("HP2_Menu.Icons.FF1",Class'Texture'));
			textureFFIcons[1] = Texture(DynamicLoadObject("HP2_Menu.Icons.FF2",Class'Texture'));
			textureFFIcons[2] = Texture(DynamicLoadObject("HP2_Menu.Icons.FF3",Class'Texture'));
		}
		//from UEExplorer because UTPT didn't decompile it -AdamJD
		Canvas.SetPos(Canvas.SizeX / 2 - (textureFFIcons[curFFIcon % 3].USize) / 2, Canvas.SizeY / 2 - (textureFFIcons[curFFIcon % 3].VSize) / 2);
		Canvas.DrawIcon(textureFFIcons[curFFIcon / 10 % 3], 1.0);
		++curFFIcon;
	}
}

auto state Idle
{
}

state SlideIn
{
	function RenderHudItemManager (Canvas Canvas, bool bMenuMode, bool bFullCutMode, bool bHalfCutMode)
	{
		fMaxBorderHeight = GetMaxBorderHeight(Canvas);
		//SetCurrBorderHeight(Canvas);
		
		DrawBorder(Canvas);
		DrawText(Canvas);
		if ( fCurrBorderHeight >= GetMaxBorderHeight(Canvas) )
		{
			GotoState('Hold');
		}
	}
	
	/*function SetCurrBorderHeight (Canvas Canvas)
	{
		//local float fMaxBorderHeight;
	
		fMaxBorderHeight = GetMaxBorderHeight(Canvas);
		if ( fCurrBorderHeight < fMaxBorderHeight )
		{
			fCurrBorderHeight += fMaxBorderHeight / 15;
		}
		if ( fCurrBorderHeight > fMaxBorderHeight )
		{
			fCurrBorderHeight = fMaxBorderHeight;
		}
	}*/

	// Omega: Untie this shit from framerate
	event Tick(float DeltaTime)
	{
		//fMaxBorderHeight = GetMaxBorderHeight(Canvas);
		if ( fCurrBorderHeight < fMaxBorderHeight )
		{
			fCurrBorderHeight += (fMaxBorderHeight) * (DeltaTime / fBorderMoveTime);
		}
		if ( fCurrBorderHeight > fMaxBorderHeight )
		{
			fCurrBorderHeight = fMaxBorderHeight;
		}
	}
	
	function BeginState ()
	{
		if ( Level.PlayerHarryActor.bIsCaptured )
		{
			bBothBordersActive = True;
		} 
		else 
		{
			bPopupBorderActive = True;
		}
		fCurrBorderHeight = 0.0;
	}
}

state Hold
{
	function RenderHudItemManager (Canvas Canvas, bool bMenuMode, bool bFullCutMode, bool bHalfCutMode)
	{
		DrawBorder(Canvas);
		DrawText(Canvas);
	}
}

state SlideOut
{
	function RenderHudItemManager (Canvas Canvas, bool bMenuMode, bool bFullCutMode, bool bHalfCutMode)
	{
		fMaxBorderHeight = GetMaxBorderHeight(Canvas);
		if ( bResetBorderHeightToMax == True )
		{
			fCurrBorderHeight = GetMaxBorderHeight(Canvas);
			bResetBorderHeightToMax = False;
		}
		//SetCurrBorderHeight(Canvas);
		DrawBorder(Canvas);
		if ( fCurrBorderHeight <= 0 )
		{
			bBothBordersActive = False;
			bPopupBorderActive = False;
			GotoState('Idle');
		}
	}
	
	/*function SetCurrBorderHeight (Canvas Canvas)
	{
		if ( fCurrBorderHeight > 0 )
		{
			fCurrBorderHeight -= GetMaxBorderHeight(Canvas) / 15;
		}
		if ( fCurrBorderHeight < 0 )
		{
			fCurrBorderHeight = 0.0;
		}
	}*/

	event Tick(float DeltaTime)
	{
		if ( fCurrBorderHeight > 0 )
		{
			fCurrBorderHeight -= (fMaxBorderHeight) * (DeltaTime / fBorderMoveTime);
		}
		if ( fCurrBorderHeight < 0 )
		{
			fCurrBorderHeight = 0.0;
		}
	}
	
	function BeginState ()
	{
		bResetBorderHeightToMax = True;
	}
}

defaultproperties
{
     textureBorder=Texture'hgame.Icons.leftPanel'
     fMaxBorderHeight=134.875
     fBorderMoveTime=0.25
     colorCutTextBlue=(R=127,G=127,B=255)
}
