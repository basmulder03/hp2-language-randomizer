class LanguagePicker extends Object;

const NUM_LANGS = 17;

// Run-statistics line types (harry.LangStatsType rows).
const LT_Dialogue = 0;
const LT_Cutscene = 1;
const LT_Chatter = 2;
const LT_Trigger = 3;
const LT_Spell = 4;
const NUM_LINE_TYPES = 5;

// Language modes (settings page "Mode" button).
const MODE_RANDOM = 0;     // weighted random pick per line
const MODE_CHARACTER = 1;  // one language per speaker for the whole run
const MODE_LEVEL = 2;      // one language per level
const MODE_SHORTEST = 3;   // the language with the shortest recording of the line
const MODE_LONGEST = 4;    // ... the longest
const MODE_CHAOS = 5;      // audio in one language, subtitle in another
const NUM_MODES = 6;

var config string LangCodes[NUM_LANGS];
var config float LangWeights[NUM_LANGS];
var config string LangNativeNames[NUM_LANGS];
var config bool bRedubEnabled;
// Settings-page options. LangEnabled is byte, not bool: UnrealScript has no
// bool arrays. 0 = excluded from the pool.
var config bool bRandomizerEnabled;
var config byte LangEnabled[NUM_LANGS];
var config bool bAllowCutsceneSkip;
var config bool bRandomizeMenu;
var config byte LangMode;
var config bool bHideLangLabel;

var string RedubCode;

var string LastResolvedLang;
var string LastResolvedDialogID;
// Chaos mode: the audio language, when it differs from LastResolvedLang
// (the subtitle language). Equal to LastResolvedLang otherwise.
var string LastResolvedAudioLang;

// Native fonts, created on first use and reused: CreateNativeFont builds a
// real GDI font and DrawText asks for it every frame. Japanese and Russian
// are separate font resources.
var Font CachedJapFont;
var Font CachedRusFont;

// Negative-caching companions to CachedJapFont/CachedRusFont. Set once a
// session's font-creation attempt for that language has failed for a
// reason that will never change within the session (fontName/fontSize
// resolution failed, or CreateNativeFont itself returned None), so
// GetFontForLanguage can give up trying every frame instead of re-running
// the whole resolution (Localize calls, LoadStringArray disk read, line-
// parsing loops, two log() calls) on every single frame a jap/rus subtitle
// stays on screen -- potentially hundreds of times for one line.
// Deliberately NOT set when Con == None (see GetFontForLanguage's own
// comment at that check): Con may legitimately become available on a
// later frame (e.g. very first frame before the console is ready), so
// that specific failure must keep retrying, unlike the other two.
var bool bJapFontAttempted;
var bool bRusFontAttempted;

// GetNativeText's caches. Loaded once (lazily) and reused for the rest of
// the session -- same "DrawText runs every frame a subtitle is on screen"
// reasoning as CachedJapFont/CachedRusFont above, but more important here:
// HpDialog.jap.backup is ~212KB/5000+ lines, so a naive re-LoadStringArray
// +re-scan on every frame would be a real, avoidable perf/stutter risk.
// Separate arrays per language (rather than one local reused across every
// LoadStringArray call) sidestep an otherwise-unconfirmed question about
// whether LoadStringArray truncates its output array to the new file's
// line count or only overwrites in place -- either way, each array here
// only ever receives exactly one file's content, loaded exactly once.
var array<string> CachedHpDialogLines;
var array<string> CachedBumpDialogLines;
var bool bJapDialogFilesLoaded;
// Same as the three vars above, for HpDialog.rus.backup/BumpDialog.rus.backup.
var array<string> CachedHpDialogLinesRus;
var array<string> CachedBumpDialogLinesRus;
var bool bRusDialogFilesLoaded;

// Last GetNativeText result, so consecutive frames showing the same
// subtitle skip the scan. Keyed on dialogID *and* language: the same line
// can be shown in Japanese once and Russian later.
var string LastNativeTextDialogID;
var string LastNativeTextLang;
var string LastNativeTextResult;
var bool bLastNativeTextValid;

// GetNativeLanguageName's cache (NativeLangNames.dat, loaded once).
var array<string> CachedNativeLangNames;
var bool bNativeLangNamesLoaded;

static function bool IsRandomizerEnabled()
{
    return default.bRandomizerEnabled;
}

static function bool IsCutsceneSkipAllowed()
{
    return default.bAllowCutsceneSkip;
}

// "redub" is opt-in-only: only eligible when the player has explicitly set
// bRedubEnabled=true via ini (it is never listed on the settings page).
static function bool IsLangEligible(int i)
{
    if (default.LangCodes[i] == default.RedubCode && !default.bRedubEnabled)
        return false;
    return default.LangEnabled[i] != 0 && default.LangWeights[i] > 0.0;
}

// --- Settings page accessors (FELangRandomizerPage) ---------------------

static function int GetNumLangs()
{
    return NUM_LANGS;
}

static function string GetLangCode(int i)
{
    return default.LangCodes[i];
}

// Never listed on the settings page: redub is ini/debug-console only.
static function bool IsHiddenLang(int i)
{
    return default.LangCodes[i] == default.RedubCode;
}

static function string GetLangDisplayName(int i)
{
    return default.LangNativeNames[i];
}

static function bool IsLangEnabled(int i)
{
    return default.LangEnabled[i] != 0;
}

static function float GetLangWeight(int i)
{
    return default.LangWeights[i];
}

// Chance (0-100) that a line resolves to language i under the current
// settings; 0 when the randomizer is off or i is not eligible.
static function float GetLangShare(int i)
{
    local int j;
    local float total;

    if (!default.bRandomizerEnabled || !IsLangEligible(i))
        return 0.0;
    for (j = 0; j < NUM_LANGS; j++)
        if (IsLangEligible(j))
            total += default.LangWeights[j];
    if (total <= 0.0)
        return 0.0;
    return 100.0 * default.LangWeights[i] / total;
}

static function SetRandomizerEnabled(bool b)
{
    default.bRandomizerEnabled = b;
    StaticSaveConfig();
}

static function bool IsLangLabelHidden()
{
    return default.bHideLangLabel;
}

static function SetLangLabelHidden(bool b)
{
    default.bHideLangLabel = b;
    StaticSaveConfig();
}

static function bool IsMenuRandomized()
{
    return default.bRandomizeMenu;
}

static function SetMenuRandomized(bool b)
{
    default.bRandomizeMenu = b;
    StaticSaveConfig();
}

// Menu text (BaseFEPage.GetLocalFEString) in a random language: each label
// gets its own pick when its page is built, so it holds for the session.
// Merged <key>_<LANG> entries come from each language's HpMenu file
// (merge_dialog_text.py). jap/rus are skipped -- the bitmap menu fonts have
// no glyphs for them -- and pol has no menu text, so those rolls retry.
static function string LocalizeMenu(string key)
{
    local int attempt;
    local string lang, s;

    if (default.bRandomizerEnabled && default.bRandomizeMenu)
    {
        for (attempt = 0; attempt < 6; attempt++)
        {
            lang = PickWeightedLang();
            if (lang == "jap" || lang == "rus")
                continue;
            s = LocalizeOrEmpty(key $ "_" $ Caps(lang), "HPMenu");
            if (s != "")
                return s;
        }
    }
    return Localize("All", key, "HPMenu");
}

static function SetCutsceneSkipAllowed(bool b)
{
    default.bAllowCutsceneSkip = b;
    StaticSaveConfig();
}

static function SetLangEnabled(int i, bool b)
{
    if (b)
        default.LangEnabled[i] = 1;
    else
        default.LangEnabled[i] = 0;
    StaticSaveConfig();
}

// Hidden redub pool toggle: ini (bRedubEnabled) or the "Redub" console
// command (harry.Redub), never the settings page.
static function bool IsRedubEnabled()
{
    return default.bRedubEnabled;
}

static function SetRedubEnabled(bool b)
{
    default.bRedubEnabled = b;
    StaticSaveConfig();
}

static function SetLangWeight(int i, float w)
{
    default.LangWeights[i] = FClamp(w, 0.0, 10.0);
    StaticSaveConfig();
}

// Settings page "Reset to defaults". Mirrors defaultproperties below (the
// config-loaded default.* values can't be used: they already hold the
// player's saved settings). bRedubEnabled is deliberately left alone -- it
// is a hidden ini/debug-console feature, not a settings-page one.
static function ResetToDefaults()
{
    local int i;

    default.bRandomizerEnabled = true;
    default.bAllowCutsceneSkip = false;
    default.bRandomizeMenu = true;
    default.LangMode = MODE_RANDOM;
    default.bHideLangLabel = false;
    for (i = 0; i < NUM_LANGS; i++)
    {
        default.LangWeights[i] = 5.0;
        default.LangEnabled[i] = 1;
    }
    StaticSaveConfig();
}

// usa text lives under _USA keys (merged from HpDialog.usa); the plain key
// is the stock (UK-worded) text, kept as a fallback.
static function string LangSubtitle(string dialogID, string lang, string localizationFile)
{
    local string s;

    s = LocalizeOrEmpty(dialogID $ "_" $ Caps(lang), localizationFile);
    if (s == "" && lang == "usa")
        s = LocalizeOrEmpty(dialogID, localizationFile);
    return s;
}

// --- Language modes -------------------------------------------------------

static function byte GetLangMode()
{
    return default.LangMode;
}

static function SetLangMode(byte m)
{
    default.LangMode = m % NUM_MODES;
    StaticSaveConfig();
}

// Language for attempt N of a line under the current mode. Per-character
// and per-level modes are deterministic for the run (seeded weighted pick);
// later attempts give that key's next choices, used when the first choice
// lacks this particular line.
static function string ChooseLang(string dialogID, Actor Context, int attempt)
{
    if (!default.bRandomizerEnabled)
        return "usa";
    if (Context != None)
    {
        if (default.LangMode == MODE_CHARACTER)
            return PickSeededLang("C:" $ GetSpeakerKey(dialogID), attempt, Context);
        if (default.LangMode == MODE_LEVEL)
            return PickSeededLang("L:" $ Caps(Context.GetURLMap()), attempt, Context);
    }
    return PickWeightedLang();
}

static function int HashString(string s)
{
    local int i, h;

    h = 5381;
    for (i = 0; i < Len(s); i++)
        h = (h * 33) ^ Asc(Mid(s, i, 1));
    return h & 0x7FFFFFFF;
}

// Per-run seed, stored on harry (travel) so per-character/per-level choices
// survive level changes and save/load, and change with every new game.
static function int GetRunSeed(Actor Context)
{
    local harry H;

    H = harry(Context.Level.PlayerHarryActor);
    if (H == None)
        return 1;
    if (H.LangRunSeed == 0)
        H.LangRunSeed = Rand(1000000000) + 1;
    return H.LangRunSeed;
}

// Weighted pick like PickWeightedLang, but with the roll derived from key.
static function string PickSeededLang(string key, int attempt, Actor Context)
{
    local int i;
    local float total, roll, running;

    for (i = 0; i < NUM_LANGS; i++)
        if (IsLangEligible(i))
            total += default.LangWeights[i];
    if (total <= 0.0)
        return "usa";

    // UnrealScript's % already yields a float.
    roll = (HashString(key $ "|" $ GetRunSeed(Context) $ "|" $ attempt) % 1000003) / 1000003.0 * total;
    for (i = 0; i < NUM_LANGS; i++)
    {
        if (!IsLangEligible(i))
            continue;
        running += default.LangWeights[i];
        if (roll < running)
            return default.LangCodes[i];
    }
    return "usa";
}

// Shortest/longest modes: among eligible languages that have this line
// (and, when localizationFile is given, its subtitle), the one whose
// recording is shortest/longest. False in other modes, when the
// randomizer is off, or without an actor to measure sounds with.
static function bool FindExtremeLang(string dialogID, string package, string localizationFile, Actor Context, out string bestLang, out Sound bestSound)
{
    local int i;
    local Sound snd;
    local float d, bestDur;
    local bool bLongest;

    if (Context == None || !default.bRandomizerEnabled)
        return false;
    if (default.LangMode != MODE_SHORTEST && default.LangMode != MODE_LONGEST)
        return false;
    bLongest = default.LangMode == MODE_LONGEST;

    bestSound = None;
    for (i = 0; i < NUM_LANGS; i++)
    {
        if (!IsLangEligible(i))
            continue;
        snd = LoadLangSound(package, default.LangCodes[i], dialogID);
        if (snd == None)
            continue;
        if (localizationFile != "" && LangSubtitle(dialogID, default.LangCodes[i], localizationFile) == "")
            continue;
        d = Context.GetSoundDuration(snd);
        if (bestSound == None || (bLongest && d > bestDur) || (!bLongest && d < bestDur))
        {
            bestSound = snd;
            bestDur = d;
            bestLang = default.LangCodes[i];
        }
    }
    return bestSound != None;
}

// "m:ss" (or "h:mm:ss") for the listening-time statistics.
static function string FormatSeconds(float Seconds)
{
    local int t, h, m, s;
    local string out;

    t = int(Seconds + 0.5);
    h = t / 3600;
    m = (t / 60) % 60;
    s = t % 60;
    if (h > 0)
    {
        out = string(h) $ ":";
        if (m < 10)
            out = out $ "0";
    }
    out = out $ string(m) $ ":";
    if (s < 10)
        out = out $ "0";
    return out $ string(s);
}

static function float SoundSeconds(Actor Context, Sound snd)
{
    if (Context == None || snd == None)
        return 0.0;
    return Context.GetSoundDuration(snd);
}

// Chaos mode: audio from one weighted pick, subtitle from a different one
// (falls back to the audio language's own text if no other language has
// this line). Needs an actor only for symmetry with the other modes.
static function bool ResolveChaos(string dialogID, string package, string localizationFile, Actor Context, out string textLang, out Sound dlgSound, out string subtitleText)
{
    local int attempt;
    local string audioLang, tryLang;

    if (default.LangMode != MODE_CHAOS || !default.bRandomizerEnabled)
        return false;
    dlgSound = None;  // out param: may arrive holding the caller's value
    for (attempt = 0; attempt < 6 && dlgSound == None; attempt++)
    {
        audioLang = PickWeightedLang();
        dlgSound = LoadLangSound(package, audioLang, dialogID);
    }
    if (dlgSound == None)
        return false;
    textLang = "";
    for (attempt = 0; attempt < 8; attempt++)
    {
        tryLang = PickWeightedLang();
        if (tryLang == audioLang)
            continue;
        subtitleText = LangSubtitle(dialogID, tryLang, localizationFile);
        if (subtitleText != "")
        {
            textLang = tryLang;
            break;
        }
    }
    if (textLang == "")
    {
        textLang = audioLang;
        subtitleText = LangSubtitle(dialogID, audioLang, localizationFile);
        if (subtitleText == "")
            return false;
    }
    SetLastResolved(textLang, audioLang, dialogID);
    return true;
}

// ReplayLine console command (harry.ReplayLine): the last subtitled line
// again, in a language other than the one it just played in. Not counted
// in the run statistics.
static function bool PickReplay(out string lang, out Sound snd, out string text)
{
    local int attempt;
    local string id, prev;

    id = default.LastResolvedDialogID;
    prev = default.LastResolvedAudioLang;
    if (id == "")
        return false;
    for (attempt = 0; attempt < 10; attempt++)
    {
        lang = PickWeightedLang();
        if (lang == prev && attempt < 9)
            continue;
        snd = LoadLangSound("AllDialog", lang, id);
        if (snd == None)
            continue;
        text = LangSubtitle(id, lang, "HPdialog");
        if (text == "")
            text = LangSubtitle(id, lang, "BumpDialog");
        if (text == "")
            continue;
        if (Left(text, 1) == "[" && InStr(text, "]") != -1)
            text = Mid(text, InStr(text, "]") + 1);
        SetLastResolved(lang, lang, id);
        return true;
    }
    return false;
}

static function string PickWeightedLang()
{
    local int i;
    local float total, roll, running;
    local int numActive;

    numActive = NUM_LANGS;

    if (!default.bRandomizerEnabled)
        return "usa";

    for (i = 0; i < numActive; i++)
    {
        // "redub" is opt-in-only: only counted toward the weighted pool
        // (and thus only ever pickable) when the player has explicitly set
        // bRedubEnabled=true via ini. Reuses the existing RedubCode var --
        // this is exactly what it looks like it was always meant for.
        if (!IsLangEligible(i))
            continue;
        total += default.LangWeights[i];
    }

    // Everything disabled or weighted to 0: behave like the randomizer is off.
    if (total <= 0.0)
        return "usa";

    roll = FRand() * total;
    running = 0.0;
    for (i = 0; i < numActive; i++)
    {
        if (!IsLangEligible(i))
            continue;
        running += default.LangWeights[i];
        if (roll <= running)
            return default.LangCodes[i];
    }
    // Deliberately NOT default.LangCodes[numActive - 1] -- that's index 16,
    // "redub" itself, which would incorrectly return the disabled language
    // if this fallback path is ever hit while bRedubEnabled is false. This
    // path should only trigger on floating-point edge cases (roll landing
    // exactly on total after the loop's <= check), but "usa" is a safe,
    // always-valid, always-enabled default -- matching the pattern
    // ResolveLine's own fallback already uses elsewhere in this file.
    return "usa";
}

// --- Run statistics ---------------------------------------------------
// Counts live on harry as travel arrays (LangStatsType/Speaker/Level), so
// they follow the player across level changes and into save games; they
// are reached through harry's LangStat* accessors (4KB context limit). Every
// language-resolution entry point takes an optional Actor context; with
// none (or no harry yet) nothing is recorded.

static function int GetLangIndex(string lang)
{
    local int i;
    for (i = 0; i < NUM_LANGS; i++)
        if (default.LangCodes[i] == lang)
            return i;
    return -1;
}

// SubstituteDialog is shared by cutscenes and gameplay delivery
// (DeliverLocalizedDialog); a captured Harry means a cutscene is running.
static function byte GuessLineType(Actor Context)
{
    local harry H;

    if (Context == None)
        return LT_Dialogue;
    if (PopupTrigger(Context) != None)
        return LT_Trigger;
    H = harry(Context.Level.PlayerHarryActor);
    if (H != None && H.bIsCaptured)
        return LT_Cutscene;
    return LT_Dialogue;
}

// "PC_Ron_WhompTut1_69" -> "RON"; anything not shaped like that -> "OTHER".
static function string GetSpeakerKey(string dialogID)
{
    local int p;
    local string rest;

    if (!(Left(dialogID, 3) ~= "PC_"))
        return "OTHER";
    rest = Mid(dialogID, 3);
    p = InStr(rest, "_");
    if (p <= 0)
        return "OTHER";
    return Caps(Left(rest, p));
}

static function RecordLine(Actor Context, string dialogID, string lang, byte LineType, optional float Seconds)
{
    local harry H;
    local int li;

    if (Context == None)
        return;
    H = harry(Context.Level.PlayerHarryActor);
    li = GetLangIndex(lang);
    if (H == None || li < 0 || LineType >= NUM_LINE_TYPES)
        return;

    // One line per played voice line, for tools/check_log.py.
    log("LanguagePicker.Played: type=" $ LineType $ " lang=" $ lang $ " id=" $ dialogID $ " map=" $ Context.GetURLMap());
    H.LangStatAdd(0, LineType, li);
    H.LangStatSeconds[li] += Seconds;
    H.LangStatAdd(1, H.LangStatRowFor(1, GetSpeakerKey(dialogID)), li);
    H.LangStatAdd(2, H.LangStatRowFor(2, Context.GetURLMap()), li);
}

// Localize() returns a "<?...?>" marker, not "", for a missing key.
static function string LocalizeOrEmpty(string key, string localizationFile)
{
    local string s;

    s = Localize("All", key, localizationFile);
    if (Left(s, 2) == "<?")
        return "";
    return s;
}

static function Sound LoadLangSound(string package, string lang, string dialogID)
{
    local Sound snd;

    // usa: the real North American recording (AllDialog_USA, imported from
    // the NA disc -- e.g. "Pink Lady" where the UK dub says "Fat Lady").
    // The installed stock AllDialog only holds the UK "Int" group, which the
    // plain lookup below also resolves to, so it is only the fallback.
    if (lang == "usa")
    {
        snd = Sound(DynamicLoadObject(package $ "_USA." $ dialogID, class'Sound', true));
        if (snd == None)
            snd = Sound(DynamicLoadObject(package $ "." $ dialogID, class'Sound', true));
        return snd;
    }
    if (lang == "int")
        return Sound(DynamicLoadObject(package $ ".Int." $ dialogID, class'Sound', true));
    return Sound(DynamicLoadObject(package $ "_" $ Caps(lang) $ "." $ dialogID, class'Sound', true));
}

// Audio-only counterpart of ResolveLine, for voice lines that have no
// subtitle (spell incantations). Deliberately leaves LastResolvedLang/
// LastResolvedDialogID untouched: nothing is displayed for these lines,
// so updating the cache would only mislabel whatever subtitle is on
// screen. Falls back to the stock AllDialog.<dialogID> lookup, so IDs that
// no language package has (e.g. Aragog's "spells3" web sound) behave
// exactly as before.
static function Sound ResolveSoundOnly(string dialogID, optional Actor Context)
{
    local int attempt;
    local string tryLang;
    local Sound snd;

    if (FindExtremeLang(dialogID, "AllDialog", "", Context, tryLang, snd))
    {
        RecordLine(Context, dialogID, tryLang, LT_Spell, SoundSeconds(Context, snd));
        return snd;
    }
    for (attempt = 0; attempt < 6; attempt++)
    {
        tryLang = ChooseLang(dialogID, Context, attempt);
        snd = LoadLangSound("AllDialog", tryLang, dialogID);
        if (snd != None)
        {
            RecordLine(Context, dialogID, tryLang, LT_Spell, SoundSeconds(Context, snd));
            return snd;
        }
    }
    snd = Sound(DynamicLoadObject("AllDialog." $ dialogID, class'Sound', true));
    if (snd != None)
        RecordLine(Context, dialogID, "usa", LT_Spell, SoundSeconds(Context, snd));
    return snd;
}

static function bool ResolveLine(string dialogID, string package, string localizationFile, out string lang, out Sound dlgSound, out string subtitleText, optional Actor Context, optional byte LineType)
{
    local int attempt;
    local string tryLang;
    local string key;

    // Shortest/longest modes: compare every eligible language's recording.
    if (FindExtremeLang(dialogID, package, localizationFile, Context, tryLang, dlgSound))
    {
        subtitleText = LangSubtitle(dialogID, tryLang, localizationFile);
        lang = tryLang;
        SetLastResolved(lang, lang, dialogID);
        RecordLine(Context, dialogID, lang, LineType, SoundSeconds(Context, dlgSound));
        return true;
    }

    // Chaos mode: audio and subtitle from two different languages.
    if (ResolveChaos(dialogID, package, localizationFile, Context, lang, dlgSound, subtitleText))
    {
        RecordLine(Context, dialogID, default.LastResolvedAudioLang, LineType, SoundSeconds(Context, dlgSound));
        return true;
    }

    for (attempt = 0; attempt < 6; attempt++)
    {
        tryLang = ChooseLang(dialogID, Context, attempt);

        // "int" is the UK dub, stored in the stock AllDialog package's Int
        // group (AllDialog.Int.<id>), not in a separate package.
        dlgSound = LoadLangSound(package, tryLang, dialogID);
        if (dlgSound == None)
            continue;

        subtitleText = LangSubtitle(dialogID, tryLang, localizationFile);
        if (subtitleText != "")
        {
            lang = tryLang;
            SetLastResolved(lang, lang, dialogID);
            RecordLine(Context, dialogID, lang, LineType, SoundSeconds(Context, dlgSound));
            return true;
        }
    }

    // Fallback: guaranteed-coverage usa package + plain-key text.
    dlgSound = Sound(DynamicLoadObject(package $ "." $ dialogID, class'Sound', true));
    subtitleText = Localize("All", dialogID, localizationFile);
    lang = "usa";
    SetLastResolved(lang, lang, dialogID);
    if (dlgSound != None)
        RecordLine(Context, dialogID, lang, LineType, SoundSeconds(Context, dlgSound));
    return dlgSound != None && subtitleText != "";
}

// Flag_* textures are imported into HGame by FlagIcons.uc with Mips=0, so
// the engine can't pick a blurry lower mip for these fixed-size HUD icons.
static function Texture GetFlagTexture(string lang)
{
    local Texture t;
    t = Texture(DynamicLoadObject("HGame.Flags.Flag_" $ Caps(lang), class'Texture', true));
    if (t == None)
        t = Texture(DynamicLoadObject("HGame.Flags.Flag_USA", class'Texture', true));
    return t;
}

static function string GetLastResolvedLang()
{
    return default.LastResolvedLang;
}

// Call right before SetSubtitleText wherever English text is shown without
// going through ResolveLine/SubstituteDialogHelper; otherwise the subtitle
// would show the language of whatever line was resolved last.
static function ResetToEnglish()
{
    SetLastResolved("usa", "usa", "");
}

static function SetLastResolved(string textLang, string audioLang, string dialogID)
{
    default.LastResolvedLang = textLang;
    default.LastResolvedAudioLang = audioLang;
    default.LastResolvedDialogID = dialogID;
}

static function string GetLastResolvedAudioLang()
{
    return default.LastResolvedAudioLang;
}

static function string ComposeSubtitle(string lang, string rawText, optional string audioLang)
{
    local int i;
    local string nativeName;

    // jap/rus: their native-script name from NativeLangNames.dat, falling
    // back to the ASCII LangNativeNames entry.
    if (lang == "jap" || lang == "rus")
        nativeName = GetNativeLanguageName(lang);

    if (nativeName == "")
    {
        for (i = 0; i < NUM_LANGS; i++)
        {
            if (default.LangCodes[i] == lang)
            {
                nativeName = default.LangNativeNames[i];
                break;
            }
        }
    }
    if (nativeName == "")
        nativeName = "English";

    // Chaos mode: name the audio language too. ASCII name on purpose -- the
    // subtitle font follows the text language, so a native-script audio
    // name (e.g. Japanese under a Western font) would render as "???".
    if (audioLang != "" && audioLang != lang && GetLangIndex(audioLang) >= 0)
        nativeName = nativeName $ " [" $ default.LangNativeNames[GetLangIndex(audioLang)] $ "]";

    return nativeName $ ": " $ rawText;
}

// `Con` must be a live Console instance (e.g. Level.PlayerHarryActor.Player.
// Console from an Actor context) -- CreateNativeFont is declared native on
// Engine.Console itself, not on Object/Actor, so it cannot be called from
// this static Object-derived class without one being handed in. Passing an
// instance reference into a static function is fine (it's calling an
// instance method through a held reference, not a cross-class static call),
// unlike the class'X'.static.Foo() rule that applies to static calls only.
static function Font GetFontForLanguage(string lang, Console Con)
{
    local string fontName;
    local int fontSize;
    local array<string> sapLines;
    local int i;
    local string linePrefix;

    // Every other language uses the standard bitmap UI font.
    if (lang != "jap" && lang != "rus")
        return None; // None signals "caller should use its existing default font"

    if (lang == "jap" && default.CachedJapFont != None)
        return default.CachedJapFont;
    if (lang == "rus" && default.CachedRusFont != None)
        return default.CachedRusFont;

    // Negative-cache short-circuit: this language's font-creation attempt
    // already failed permanently earlier this session -- see
    // bJapFontAttempted/bRusFontAttempted's own declaration comment above.
    // Checked before Con == None below on purpose: once this flag is set,
    // there is no need to even look at Con again.
    if (lang == "jap" && default.bJapFontAttempted)
        return None;
    if (lang == "rus" && default.bRusFontAttempted)
        return None;

    if (Con == None)
        return None;

    if (lang == "jap")
    {
        // SAPFont.jap (system/SAPFont.jap) is NOT a loadable Font package --
        // confirmed by inspecting its bytes: it's a plain-text, CRLF, Shift-JIS
        // "[all]\r\nFont1Name=...\r\nFont1Size=14\r\n..." key/value file.
        // Font2/Font2Size ("Med") is used here to match the size tier
        // HPHud.DrawCutStyleText itself falls back to first (LocalMedFont) when
        // no explicit fontText is supplied for the default/Latin path -- see
        // GetNativeText's caller-side note on DrawCutStyleText's auto-shrink
        // fallback for why staying close to that tier matters.
        //
        // Try Localize() first (cheap, and correct if this session's fixed
        // Engine.Engine.Language ever isn't "int"). On a miss, do NOT fall
        // back to reading SAPFont.jap's Font2Name off disk the way rus does
        // below -- byte-inspection of the real file confirmed its
        // Font2Name value is genuinely Shift-JIS-encoded (bytes 82 6c 82 72
        // 20 82 6f ba de bc af b8, i.e. the Japanese GDI font family name
        // "MS PGothic"), and LoadStringArray does no Shift-JIS
        // decoding -- reading it would just produce cp1252 mojibake as the
        // font name. CreateNativeFont's underlying GDI font mapper doesn't
        // fail on an unmatched name either, it silently substitutes some
        // other font, so a mojibake name would get permanently cached as a
        // WRONG font for the whole session -- worse than the clean None
        // fallback that existed before this fix. Instead, the correct
        // ASCII GDI family name is hardcoded directly here (safe: pure
        // ASCII, no encoding risk). fontSize=14 matches the real Font2Size
        // value in SAPFont.jap, which IS plain ASCII and was never the
        // problem.
        fontName = Localize("all", "Font2Name", "SAPFont");
        fontSize = int(Localize("all", "Font2Size", "SAPFont"));
        if (fontName == "" || fontSize <= 0)
        {
            fontName = "MS PGothic";
            fontSize = 14;
        }
    }
    else // lang == "rus"
    {
        // Localize() always resolves against the session language ("int"),
        // and there is no SAPFont.int, so this usually returns "". Fall back
        // to reading SAPFont.rus directly (its font name is plain ASCII).
        fontName = Localize("all", "Font2Name", "SAPFont");
        fontSize = int(Localize("all", "Font2Size", "SAPFont"));
        if (fontName == "" || fontSize <= 0)
        {
            LoadStringArray(sapLines, "SAPFont.rus");

            linePrefix = "Font2Name=";
            for (i = 0; i < sapLines.Length; i++)
            {
                if (Left(sapLines[i], Len(linePrefix)) == linePrefix)
                {
                    fontName = Mid(sapLines[i], Len(linePrefix));
                    break;
                }
            }
            // SAPFont.rus is plain CRLF text -- defensively strip a
            // trailing carriage return if LoadStringArray's line-splitting
            // ever leaves one in place, since CreateNativeFont does an
            // exact Windows GDI font-family-name match and a stray
            // trailing character would silently break that match (unlike
            // GetNativeText's dialogue text below, where a stray trailing
            // character at the end of a subtitle line is harmless).
            if (Right(fontName, 1) == Chr(13))
                fontName = Left(fontName, Len(fontName) - 1);

            linePrefix = "Font2Size=";
            for (i = 0; i < sapLines.Length; i++)
            {
                if (Left(sapLines[i], Len(linePrefix)) == linePrefix)
                {
                    fontSize = int(Mid(sapLines[i], Len(linePrefix)));
                    break;
                }
            }
        }
    }

    // Diagnostic: which source supplied the font name, if any.
    log("LanguagePicker.GetFontForLanguage: lang=" $ lang $ " fontName=" $ fontName $ " fontSize=" $ string(fontSize));

    if (fontName == "" || fontSize <= 0)
    {
        // Permanent failure for this session -- fontName/fontSize never
        // change once resolved, so there's nothing a later frame could fix.
        if (lang == "jap")
            default.bJapFontAttempted = true;
        else
            default.bRusFontAttempted = true;
        return None;
    }

    if (lang == "jap")
    {
        default.CachedJapFont = Con.CreateNativeFont(fontName, fontSize);
        // Attempted flag set right after CreateNativeFont regardless of
        // outcome -- a session only ever gets one real attempt, whether it
        // succeeds (CachedJapFont short-circuits future calls on its own)
        // or fails (this flag short-circuits them instead).
        default.bJapFontAttempted = true;
        // Diagnostic: whether CreateNativeFont succeeded for this name/size.
        log("LanguagePicker.GetFontForLanguage: CreateNativeFont(jap) result=" $ (default.CachedJapFont != None ? "SUCCESS" : "FAILED"));
        return default.CachedJapFont;
    }

    default.CachedRusFont = Con.CreateNativeFont(fontName, fontSize);
    default.bRusFontAttempted = true;
    log("LanguagePicker.GetFontForLanguage: CreateNativeFont(rus) result=" $ (default.CachedRusFont != None ? "SUCCESS" : "FAILED"));
    return default.CachedRusFont;
}

static function string GetLastResolvedDialogID()
{
    return default.LastResolvedDialogID;
}

// The native-script subtitle for dialogID from HpDialog/BumpDialog.<lang>.backup
// (UTF-16 files in System/). Covers jap and rus; returns "" for any other
// language or on a miss, so the caller uses the merged cp1252 text.
static function string GetNativeText(string dialogID, string lang)
{
    local int i;
    local string linePrefix;
    local string result;

    if (lang != "jap" && lang != "rus")
        return "";

    // Same line and language as last time (DrawText calls this every frame):
    // skip the scan.
    if (default.bLastNativeTextValid && default.LastNativeTextDialogID == dialogID && default.LastNativeTextLang == lang)
        return default.LastNativeTextResult;

    if (lang == "jap")
    {
        if (!default.bJapDialogFilesLoaded)
        {
            // LoadStringArray fills the array in place; its return value
            // is unused (the stock callers check Length afterwards too).
            LoadStringArray(default.CachedHpDialogLines, "HpDialog.jap.backup");
            LoadStringArray(default.CachedBumpDialogLines, "BumpDialog.jap.backup");
            default.bJapDialogFilesLoaded = true;
        }
    }
    else // lang == "rus"
    {
        if (!default.bRusDialogFilesLoaded)
        {
            // Same as the jap branch, for the Russian files.
            LoadStringArray(default.CachedHpDialogLinesRus, "HpDialog.rus.backup");
            LoadStringArray(default.CachedBumpDialogLinesRus, "BumpDialog.rus.backup");
            default.bRusDialogFilesLoaded = true;
        }
    }

    // Case-insensitive match below: the engine can hand SubstituteDialog
    // a Sound whose Name casing differs from the .backup file key (e.g.
    // pc_nar_privetintro_65 vs PC_Nar_PrivetIntro_65), and a missed
    // lookup falls back to the cp1252 text -- rendered as "???".
    linePrefix = dialogID $ "=";
    result = "";

    if (lang == "jap")
    {
        for (i = 0; i < default.CachedHpDialogLines.Length; i++)
        {
            if (Caps(Left(default.CachedHpDialogLines[i], Len(linePrefix))) == Caps(linePrefix))
            {
                result = Mid(default.CachedHpDialogLines[i], Len(linePrefix));
                break;
            }
        }

        if (result == "")
        {
            for (i = 0; i < default.CachedBumpDialogLines.Length; i++)
            {
                if (Caps(Left(default.CachedBumpDialogLines[i], Len(linePrefix))) == Caps(linePrefix))
                {
                    result = Mid(default.CachedBumpDialogLines[i], Len(linePrefix));
                    break;
                }
            }
        }
    }
    else // lang == "rus"
    {
        for (i = 0; i < default.CachedHpDialogLinesRus.Length; i++)
        {
            if (Caps(Left(default.CachedHpDialogLinesRus[i], Len(linePrefix))) == Caps(linePrefix))
            {
                result = Mid(default.CachedHpDialogLinesRus[i], Len(linePrefix));
                break;
            }
        }

        if (result == "")
        {
            for (i = 0; i < default.CachedBumpDialogLinesRus.Length; i++)
            {
                if (Caps(Left(default.CachedBumpDialogLinesRus[i], Len(linePrefix))) == Caps(linePrefix))
                {
                    result = Mid(default.CachedBumpDialogLinesRus[i], Len(linePrefix));
                    break;
                }
            }
        }
    }

    // The .backup files hold the raw line, including its leading facial-
    // expression tag ("[Happy]..."). Every stock display path strips that
    // via Actor.HandleFacialExpression before SetSubtitleText, but DrawText
    // swaps this native text in afterwards, so strip it here the same way
    // (one leading "[...]" tag only, matching the stock behavior).
    if (Left(result, 1) == "[" && InStr(result, "]") != -1)
        result = Mid(result, InStr(result, "]") + 1);

    default.LastNativeTextDialogID = dialogID;
    default.LastNativeTextLang = lang;
    default.LastNativeTextResult = result;
    default.bLastNativeTextValid = true;

    return result; // "" falls back to merged-file (cp1252 "?"-degraded) text on any miss
}

// The native-script display name for jap/rus from NativeLangNames.dat (a
// UTF-16 file: this .uc file is cp1252 and can't hold those characters).
// Returns "" on any miss, so ComposeSubtitle falls back to LangNativeNames.
static function string GetNativeLanguageName(string lang)
{
    local int i;
    local string linePrefix;

    if (!default.bNativeLangNamesLoaded)
    {
        LoadStringArray(default.CachedNativeLangNames, "NativeLangNames.dat");
        default.bNativeLangNamesLoaded = true;
    }

    linePrefix = lang $ "=";
    for (i = 0; i < default.CachedNativeLangNames.Length; i++)
    {
        if (Left(default.CachedNativeLangNames[i], Len(linePrefix)) == linePrefix)
            return Mid(default.CachedNativeLangNames[i], Len(linePrefix));
    }

    return "";
}

// Shared body of the SubstituteDialog overrides (HPawn, harry, PopupTrigger).
// Cutscene Say/Talk and DeliverLocalizedDialog resolve the stock sound and
// text, then call SubstituteDialog before playing it. The hook gets the
// resolved Sound, not the line ID, so the ID is recovered from the sound's
// object name (string(InSound.Name), e.g. "PC_Ara_Adv9aForest_10").
// On any miss the stock sound and text are kept.
static function SubstituteDialogHelper(Sound InSound, string InTxt, out Sound Replacement, out string ReplacementTxt, string package, string localizationFile, optional Actor Context)
{
    local string dialogID;
    local string pickedLang;
    local Sound resolvedSound;
    local string resolvedText;

    Replacement = InSound;
    ReplacementTxt = InTxt;

    if (InSound == None)
    {
        // No dialogID to recover -- but the cache must still be refreshed
        // for THIS line, or DrawText will keep showing whatever language
        // the previous successfully-resolved line picked, laid over this
        // line's actual (unsubstituted, English) text. Mirrors ResolveLine's
        // own fallback, which always sets lang="usa" before returning.
        ResetToEnglish();
        return;
    }

    dialogID = string(InSound.Name);
    if (dialogID == "")
    {
        // dialogID is provably "" here (just checked above), so this is the
        // exact same reset as the InSound == None path -- ResetToEnglish()
        // hardcodes DialogID="" too.
        ResetToEnglish();
        return;
    }

    if (ResolveLine(dialogID, package, localizationFile, pickedLang, resolvedSound, resolvedText, Context, GuessLineType(Context)))
    {
        if (resolvedSound != None)
            Replacement = resolvedSound;
        if (resolvedText != "")
            ReplacementTxt = resolvedText;
    }

    // Verification log for the InSound.Name -> dialogID recovery approach
    // (the one genuinely unconfirmed assumption in this patch) -- check
    // this line against a known cutscene dialogID next time a cutscene
    // plays, via -log.
    log("LanguagePicker.SubstituteDialogHelper: InSound.Name=" $ dialogID $ " -> lang=" $ pickedLang $ " text=" $ ReplacementTxt);
}

exec static function DebugSpamLine(string dialogID, int count)
{
    local int i;
    local string lang, subtitleText;
    local Sound dlgSound;

    for (i = 0; i < count; i++)
    {
        if (ResolveLine(dialogID, "AllDialog", "HPdialog", lang, dlgSound, subtitleText))
            log("LanguagePicker.DebugSpamLine: " $ dialogID $ " -> " $ lang $ " | " $ subtitleText);
        else
            log("LanguagePicker.DebugSpamLine: " $ dialogID $ " -> NO SOUND/TEXT FOUND for any language");
    }
}

defaultproperties
{
    LangCodes(0)="bra"
    LangCodes(1)="dan"
    LangCodes(2)="dut"
    LangCodes(3)="fin"
    LangCodes(4)="fre"
    LangCodes(5)="ger"
    LangCodes(6)="ita"
    LangCodes(7)="jap"
    LangCodes(8)="nor"
    LangCodes(9)="pol"
    LangCodes(10)="por"
    LangCodes(11)="rus"
    LangCodes(12)="spa"
    LangCodes(13)="swe"
    LangCodes(14)="usa"
    LangCodes(15)="int"
    LangCodes(16)="redub"
    LangWeights(0)=5.0
    LangWeights(1)=5.0
    LangWeights(2)=5.0
    LangWeights(3)=5.0
    LangWeights(4)=5.0
    LangWeights(5)=5.0
    LangWeights(6)=5.0
    LangWeights(7)=5.0
    LangWeights(8)=5.0
    LangWeights(9)=5.0
    LangWeights(10)=5.0
    LangWeights(11)=5.0
    LangWeights(12)=5.0
    LangWeights(13)=5.0
    LangWeights(14)=5.0
    LangWeights(15)=5.0
    LangWeights(16)=5.0
    bRandomizerEnabled=true
    // Off by default: cutscenes are where most of the voice lines are.
    bAllowCutsceneSkip=false
    bRandomizeMenu=true
    LangMode=0
    bHideLangLabel=false
    LangEnabled(0)=1
    LangEnabled(1)=1
    LangEnabled(2)=1
    LangEnabled(3)=1
    LangEnabled(4)=1
    LangEnabled(5)=1
    LangEnabled(6)=1
    LangEnabled(7)=1
    LangEnabled(8)=1
    LangEnabled(9)=1
    LangEnabled(10)=1
    LangEnabled(11)=1
    LangEnabled(12)=1
    LangEnabled(13)=1
    LangEnabled(14)=1
    LangEnabled(15)=1
    LangEnabled(16)=1
    // Display names in cp1252, as the game's text pipeline expects. The
    // jap/rus entries are ASCII fallbacks; the real native-script names come
    // from NativeLangNames.dat (see GetNativeLanguageName).
    LangNativeNames(0)="Português"
    LangNativeNames(1)="Dansk"
    LangNativeNames(2)="Nederlands"
    LangNativeNames(3)="Suomi"
    LangNativeNames(4)="Français"
    LangNativeNames(5)="Deutsch"
    LangNativeNames(6)="Italiano"
    LangNativeNames(7)="Japanese"
    LangNativeNames(8)="Norsk"
    LangNativeNames(9)="Polski"
    LangNativeNames(10)="Português"
    LangNativeNames(11)="Russian"
    LangNativeNames(12)="Español"
    LangNativeNames(13)="Svenska"
    LangNativeNames(14)="English"
    LangNativeNames(15)="English (UK)"
    LangNativeNames(16)="Redub"
    bRedubEnabled=false
    RedubCode="redub"
}
