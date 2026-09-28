//================================================================================
// FlagIcons.
//
// Holder class for the language flag textures, imported into HGame as
// HGame.Flags.Flag_<CODE> (see LanguagePicker.GetFlagTexture).
//
// - Sources are PNG (tools/scripts/generate_flags.py -> assets/build/flags),
//   copied by tools/build.sh to HGame/Textures/Flags/. #exec paths resolve
//   relative to the package folder (HGame/), not System/; a missing file
//   only gives an ExecWarning while `ucc make` still reports success.
// - Mips=0: a single mip level, so the engine can never pick a blurry lower
//   mip for these fixed-size HUD icons.
// - COMPRESSION=P8 with Flags=2, like the stock palettized UI icons.
//================================================================================

class FlagIcons extends Object;

#exec Texture Import File=Textures\Flags\Flag_BRA.PNG GROUP=Flags Name=Flag_BRA COMPRESSION=P8 UPSCALE=1 Mips=0 Flags=2
#exec Texture Import File=Textures\Flags\Flag_DAN.PNG GROUP=Flags Name=Flag_DAN COMPRESSION=P8 UPSCALE=1 Mips=0 Flags=2
#exec Texture Import File=Textures\Flags\Flag_DUT.PNG GROUP=Flags Name=Flag_DUT COMPRESSION=P8 UPSCALE=1 Mips=0 Flags=2
#exec Texture Import File=Textures\Flags\Flag_FIN.PNG GROUP=Flags Name=Flag_FIN COMPRESSION=P8 UPSCALE=1 Mips=0 Flags=2
#exec Texture Import File=Textures\Flags\Flag_FRE.PNG GROUP=Flags Name=Flag_FRE COMPRESSION=P8 UPSCALE=1 Mips=0 Flags=2
#exec Texture Import File=Textures\Flags\Flag_GER.PNG GROUP=Flags Name=Flag_GER COMPRESSION=P8 UPSCALE=1 Mips=0 Flags=2
#exec Texture Import File=Textures\Flags\Flag_INT.PNG GROUP=Flags Name=Flag_INT COMPRESSION=P8 UPSCALE=1 Mips=0 Flags=2
#exec Texture Import File=Textures\Flags\Flag_ITA.PNG GROUP=Flags Name=Flag_ITA COMPRESSION=P8 UPSCALE=1 Mips=0 Flags=2
#exec Texture Import File=Textures\Flags\Flag_JAP.PNG GROUP=Flags Name=Flag_JAP COMPRESSION=P8 UPSCALE=1 Mips=0 Flags=2
#exec Texture Import File=Textures\Flags\Flag_NOR.PNG GROUP=Flags Name=Flag_NOR COMPRESSION=P8 UPSCALE=1 Mips=0 Flags=2
#exec Texture Import File=Textures\Flags\Flag_POL.PNG GROUP=Flags Name=Flag_POL COMPRESSION=P8 UPSCALE=1 Mips=0 Flags=2
#exec Texture Import File=Textures\Flags\Flag_POR.PNG GROUP=Flags Name=Flag_POR COMPRESSION=P8 UPSCALE=1 Mips=0 Flags=2
#exec Texture Import File=Textures\Flags\Flag_REDUB.PNG GROUP=Flags Name=Flag_REDUB COMPRESSION=P8 UPSCALE=1 Mips=0 Flags=2
#exec Texture Import File=Textures\Flags\Flag_RUS.PNG GROUP=Flags Name=Flag_RUS COMPRESSION=P8 UPSCALE=1 Mips=0 Flags=2
#exec Texture Import File=Textures\Flags\Flag_SPA.PNG GROUP=Flags Name=Flag_SPA COMPRESSION=P8 UPSCALE=1 Mips=0 Flags=2
#exec Texture Import File=Textures\Flags\Flag_SWE.PNG GROUP=Flags Name=Flag_SWE COMPRESSION=P8 UPSCALE=1 Mips=0 Flags=2
#exec Texture Import File=Textures\Flags\Flag_USA.PNG GROUP=Flags Name=Flag_USA COMPRESSION=P8 UPSCALE=1 Mips=0 Flags=2
