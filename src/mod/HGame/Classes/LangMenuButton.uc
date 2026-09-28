//================================================================================
// LangMenuButton.
//
// HPMenuRaisedButton with a caller-chosen width: the stock BeforePaint
// forces WinWidth = 180 every frame, which made buttons on the language
// settings/statistics pages overlap each other and their labels. Same
// text placement as the stock version, just using ButtonWidth.
//================================================================================

class LangMenuButton extends HPMenuRaisedButton;

var float ButtonWidth;

function BeforePaint (Canvas C, float X, float Y)
{
	local float W;
	local float H;

	WinWidth = ButtonWidth;
	WinHeight = 24.0;
	TextSize(C,Text,W,H);

	TextY = ((WinHeight - H) * Class'M212HScale'.Static.UWindowGetHeightScale(Root)) / 2;
	switch (Align)
	{
		case TA_Left:
			TextX = textOffsetX;
			break;
		case TA_Right:
			TextX = WinWidth - W - textOffsetX;
			break;
		case TA_Center:
			TextX = (WinWidth - W) / 2;
			break;
	}
}

defaultproperties
{
     ButtonWidth=180.0
}
