package main

import "core:math"
import "core:math/linalg"

FontAtlasInfo :: struct {
  Id : i32,
  X : i32,
  Y : i32,
  Width : i32,
  Height : i32,
  OffsetX : i32,
  OffsetY : i32,
  AdvanceX : i32,
  Letter : string,
}

FONT_ATLAS_WIDTH  : i32 = 282
FONT_ATLAS_HEIGHT : i32 = 356
FONT_ATLAS_LINE_HEIGHT : i32 = 50

CalcTextSize :: proc(text : string, out_isMultiLine: ^bool = nil) -> [2]i32 {
  result : [2]i32
  line   : [2]i32
  for c in text {
    if c == '\n' {
      result = linalg.max(result, line)
      line = {}
      continue
    }
    line.x += FONT_ATLAS_INFO[c - 32].AdvanceX
    line.y = math.max(result.y, FONT_ATLAS_INFO[c - 32].Height)
  }
  result = linalg.max(result, line)
  return result
}

FONT_ATLAS_INFO := [?]FontAtlasInfo {
  { Id=32     ,X=147   ,Y=313   ,Width=0     ,Height=0     ,OffsetX=0     ,OffsetY=33    ,AdvanceX=10   ,Letter="space" },
  { Id=33     ,X=129   ,Y=220   ,Width=15    ,Height=33    ,OffsetX=2     ,OffsetY=0     ,AdvanceX=10   ,Letter="!" },
  { Id=34     ,X=219   ,Y=286   ,Width=23    ,Height=19    ,OffsetX=0     ,OffsetY=0     ,AdvanceX=16   ,Letter="\"" },
  { Id=35     ,X=191   ,Y=45    ,Width=33    ,Height=33    ,OffsetX=2     ,OffsetY=0     ,AdvanceX=28   ,Letter="#" },
  { Id=36     ,X=201   ,Y=2     ,Width=25    ,Height=35    ,OffsetX=2     ,OffsetY=0     ,AdvanceX=20   ,Letter="$" },
  { Id=37     ,X=80    ,Y=45    ,Width=35    ,Height=33    ,OffsetX=2     ,OffsetY=0     ,AdvanceX=30   ,Letter="%" },
  { Id=38     ,X=107   ,Y=80    ,Width=31    ,Height=33    ,OffsetX=2     ,OffsetY=0     ,AdvanceX=26   ,Letter="&" },
  { Id=39     ,X=19    ,Y=313   ,Width=13    ,Height=19    ,OffsetX=2     ,OffsetY=0     ,AdvanceX=8    ,Letter="'" },
  { Id=40     ,X=84    ,Y=2     ,Width=19    ,Height=37    ,OffsetX=0     ,OffsetY=0     ,AdvanceX=12   ,Letter="(" },
  { Id=41     ,X=105   ,Y=2     ,Width=19    ,Height=37    ,OffsetX=0     ,OffsetY=0     ,AdvanceX=12   ,Letter=")" },
  { Id=42     ,X=244   ,Y=286   ,Width=23    ,Height=19    ,OffsetX=0     ,OffsetY=0     ,AdvanceX=16   ,Letter="*" },
  { Id=43     ,X=169   ,Y=286   ,Width=21    ,Height=21    ,OffsetX=0     ,OffsetY=4     ,AdvanceX=14   ,Letter="+" },
  { Id=44     ,X=2     ,Y=313   ,Width=15    ,Height=19    ,OffsetX=2     ,OffsetY=18    ,AdvanceX=10   ,Letter="," },
  { Id=45     ,X=124   ,Y=313   ,Width=21    ,Height=13    ,OffsetX=2     ,OffsetY=10    ,AdvanceX=16   ,Letter="-" },
  { Id=46     ,X=63    ,Y=313   ,Width=15    ,Height=15    ,OffsetX=2     ,OffsetY=18    ,AdvanceX=10   ,Letter="." },
  { Id=47     ,X=255   ,Y=2     ,Width=23    ,Height=35    ,OffsetX=4     ,OffsetY=0     ,AdvanceX=20   ,Letter="/" },
  { Id=48     ,X=219   ,Y=115   ,Width=27    ,Height=33    ,OffsetX=2     ,OffsetY=0     ,AdvanceX=22   ,Letter="0" },
  { Id=49     ,X=56    ,Y=220   ,Width=23    ,Height=33    ,OffsetX=2     ,OffsetY=0     ,AdvanceX=18   ,Letter="1" },
  { Id=50     ,X=31    ,Y=185   ,Width=25    ,Height=33    ,OffsetX=2     ,OffsetY=0     ,AdvanceX=20   ,Letter="2" },
  { Id=51     ,X=58    ,Y=185   ,Width=25    ,Height=33    ,OffsetX=2     ,OffsetY=0     ,AdvanceX=20   ,Letter="3" },
  { Id=52     ,X=2     ,Y=115   ,Width=29    ,Height=33    ,OffsetX=0     ,OffsetY=0     ,AdvanceX=22   ,Letter="4" },
  { Id=53     ,X=85    ,Y=185   ,Width=25    ,Height=33    ,OffsetX=2     ,OffsetY=0     ,AdvanceX=20   ,Letter="5" },
  { Id=54     ,X=112   ,Y=185   ,Width=25    ,Height=33    ,OffsetX=2     ,OffsetY=0     ,AdvanceX=20   ,Letter="6" },
  { Id=55     ,X=248   ,Y=115   ,Width=27    ,Height=33    ,OffsetX=0     ,OffsetY=0     ,AdvanceX=20   ,Letter="7" },
  { Id=56     ,X=139   ,Y=185   ,Width=25    ,Height=33    ,OffsetX=2     ,OffsetY=0     ,AdvanceX=20   ,Letter="8" },
  { Id=57     ,X=2     ,Y=150   ,Width=27    ,Height=33    ,OffsetX=2     ,OffsetY=0     ,AdvanceX=22   ,Letter="9" },
  { Id=58     ,X=152   ,Y=286   ,Width=15    ,Height=25    ,OffsetX=2     ,OffsetY=4     ,AdvanceX=10   ,Letter=":" },
  { Id=59     ,X=222   ,Y=220   ,Width=17    ,Height=31    ,OffsetX=2     ,OffsetY=8     ,AdvanceX=12   ,Letter=";" },
  { Id=60     ,X=241   ,Y=220   ,Width=27    ,Height=29    ,OffsetX=0     ,OffsetY=2     ,AdvanceX=20   ,Letter="<" },
  { Id=61     ,X=192   ,Y=286   ,Width=25    ,Height=19    ,OffsetX=0     ,OffsetY=8     ,AdvanceX=18   ,Letter="=" },
  { Id=62     ,X=2     ,Y=255   ,Width=27    ,Height=29    ,OffsetX=2     ,OffsetY=2     ,AdvanceX=22   ,Letter=">" },
  { Id=63     ,X=166   ,Y=185   ,Width=25    ,Height=33    ,OffsetX=2     ,OffsetY=0     ,AdvanceX=20   ,Letter="?" },
  { Id=64     ,X=226   ,Y=45    ,Width=33    ,Height=33    ,OffsetX=2     ,OffsetY=4     ,AdvanceX=28   ,Letter="@" },
  { Id=65     ,X=2     ,Y=80    ,Width=33    ,Height=33    ,OffsetX=0     ,OffsetY=0     ,AdvanceX=26   ,Letter="A" },
  { Id=66     ,X=31    ,Y=150   ,Width=27    ,Height=33    ,OffsetX=2     ,OffsetY=0     ,AdvanceX=22   ,Letter="B" },
  { Id=67     ,X=140   ,Y=80    ,Width=31    ,Height=33    ,OffsetX=0     ,OffsetY=0     ,AdvanceX=24   ,Letter="C" },
  { Id=68     ,X=173   ,Y=80    ,Width=31    ,Height=33    ,OffsetX=2     ,OffsetY=0     ,AdvanceX=26   ,Letter="D" },
  { Id=69     ,X=193   ,Y=185   ,Width=25    ,Height=33    ,OffsetX=2     ,OffsetY=0     ,AdvanceX=20   ,Letter="E" },
  { Id=70     ,X=220   ,Y=185   ,Width=25    ,Height=33    ,OffsetX=2     ,OffsetY=0     ,AdvanceX=20   ,Letter="F" },
  { Id=71     ,X=117   ,Y=45    ,Width=35    ,Height=33    ,OffsetX=0     ,OffsetY=0     ,AdvanceX=28   ,Letter="G" },
  { Id=72     ,X=33    ,Y=115   ,Width=29    ,Height=33    ,OffsetX=2     ,OffsetY=0     ,AdvanceX=24   ,Letter="H" },
  { Id=73     ,X=146   ,Y=220   ,Width=15    ,Height=33    ,OffsetX=2     ,OffsetY=0     ,AdvanceX=10   ,Letter="I" },
  { Id=74     ,X=247   ,Y=185   ,Width=25    ,Height=33    ,OffsetX=0     ,OffsetY=0     ,AdvanceX=18   ,Letter="J" },
  { Id=75     ,X=206   ,Y=80    ,Width=31    ,Height=33    ,OffsetX=2     ,OffsetY=0     ,AdvanceX=26   ,Letter="K" },
  { Id=76     ,X=81    ,Y=220   ,Width=23    ,Height=33    ,OffsetX=2     ,OffsetY=0     ,AdvanceX=18   ,Letter="L" },
  { Id=77     ,X=2     ,Y=45    ,Width=37    ,Height=33    ,OffsetX=0     ,OffsetY=0     ,AdvanceX=30   ,Letter="M" },
  { Id=78     ,X=37    ,Y=80    ,Width=33    ,Height=33    ,OffsetX=2     ,OffsetY=0     ,AdvanceX=28   ,Letter="N" },
  { Id=79     ,X=154   ,Y=45    ,Width=35    ,Height=33    ,OffsetX=0     ,OffsetY=0     ,AdvanceX=28   ,Letter="O" },
  { Id=80     ,X=60    ,Y=150   ,Width=27    ,Height=33    ,OffsetX=2     ,OffsetY=0     ,AdvanceX=22   ,Letter="P" },
  { Id=81     ,X=164   ,Y=2     ,Width=35    ,Height=35    ,OffsetX=0     ,OffsetY=0     ,AdvanceX=28   ,Letter="Q" },
  { Id=82     ,X=64    ,Y=115   ,Width=29    ,Height=33    ,OffsetX=2     ,OffsetY=0     ,AdvanceX=24   ,Letter="R" },
  { Id=83     ,X=2     ,Y=220   ,Width=25    ,Height=33    ,OffsetX=2     ,OffsetY=0     ,AdvanceX=20   ,Letter="S" },
  { Id=84     ,X=89    ,Y=150   ,Width=27    ,Height=33    ,OffsetX=0     ,OffsetY=0     ,AdvanceX=20   ,Letter="T" },
  { Id=85     ,X=95    ,Y=115   ,Width=29    ,Height=33    ,OffsetX=2     ,OffsetY=0     ,AdvanceX=24   ,Letter="U" },
  { Id=86     ,X=72    ,Y=80    ,Width=33    ,Height=33    ,OffsetX=0     ,OffsetY=0     ,AdvanceX=26   ,Letter="V" },
  { Id=87     ,X=41    ,Y=45    ,Width=37    ,Height=33    ,OffsetX=0     ,OffsetY=0     ,AdvanceX=30   ,Letter="W" },
  { Id=88     ,X=126   ,Y=115   ,Width=29    ,Height=33    ,OffsetX=2     ,OffsetY=0     ,AdvanceX=24   ,Letter="X" },
  { Id=89     ,X=239   ,Y=80    ,Width=31    ,Height=33    ,OffsetX=0     ,OffsetY=0     ,AdvanceX=24   ,Letter="Y" },
  { Id=90     ,X=157   ,Y=115   ,Width=29    ,Height=33    ,OffsetX=0     ,OffsetY=0     ,AdvanceX=22   ,Letter="Z" },
  { Id=91     ,X=126   ,Y=2     ,Width=17    ,Height=37    ,OffsetX=2     ,OffsetY=0     ,AdvanceX=12   ,Letter="[" },
  { Id=92     ,X=228   ,Y=2     ,Width=25    ,Height=35    ,OffsetX=0     ,OffsetY=0     ,AdvanceX=18   ,Letter="\\" },
  { Id=93     ,X=145   ,Y=2     ,Width=17    ,Height=37    ,OffsetX=0     ,OffsetY=0     ,AdvanceX=10   ,Letter="]" },
  { Id=94     ,X=31    ,Y=255   ,Width=31    ,Height=27    ,OffsetX=2     ,OffsetY=0     ,AdvanceX=26   ,Letter="^" },
  { Id=95     ,X=97    ,Y=313   ,Width=25    ,Height=13    ,OffsetX=2     ,OffsetY=24    ,AdvanceX=20   ,Letter="_" },
  { Id=96     ,X=80    ,Y=313   ,Width=15    ,Height=15    ,OffsetX=0     ,OffsetY=0     ,AdvanceX=8    ,Letter="`" },
  { Id=97     ,X=140   ,Y=255   ,Width=27    ,Height=25    ,OffsetX=2     ,OffsetY=8     ,AdvanceX=22   ,Letter="a" },
  { Id=98     ,X=118   ,Y=150   ,Width=27    ,Height=33    ,OffsetX=2     ,OffsetY=0     ,AdvanceX=22   ,Letter="b" },
  { Id=99     ,X=56    ,Y=286   ,Width=23    ,Height=25    ,OffsetX=2     ,OffsetY=8     ,AdvanceX=18   ,Letter="c" },
  { Id=100    ,X=147   ,Y=150   ,Width=27    ,Height=33    ,OffsetX=2     ,OffsetY=0     ,AdvanceX=22   ,Letter="d" },
  { Id=101    ,X=198   ,Y=255   ,Width=25    ,Height=25    ,OffsetX=2     ,OffsetY=8     ,AdvanceX=20   ,Letter="e" },
  { Id=102    ,X=106   ,Y=220   ,Width=21    ,Height=33    ,OffsetX=0     ,OffsetY=0     ,AdvanceX=14   ,Letter="f" },
  { Id=103    ,X=176   ,Y=150   ,Width=27    ,Height=33    ,OffsetX=2     ,OffsetY=8     ,AdvanceX=22   ,Letter="g" },
  { Id=104    ,X=29    ,Y=220   ,Width=25    ,Height=33    ,OffsetX=2     ,OffsetY=0     ,AdvanceX=20   ,Letter="h" },
  { Id=105    ,X=163   ,Y=220   ,Width=15    ,Height=33    ,OffsetX=2     ,OffsetY=0     ,AdvanceX=10   ,Letter="i" },
  { Id=106    ,X=2     ,Y=2     ,Width=19    ,Height=41    ,OffsetX=-2    ,OffsetY=0     ,AdvanceX=10   ,Letter="j" },
  { Id=107    ,X=205   ,Y=150   ,Width=27    ,Height=33    ,OffsetX=2     ,OffsetY=0     ,AdvanceX=22   ,Letter="k" },
  { Id=108    ,X=180   ,Y=220   ,Width=15    ,Height=33    ,OffsetX=2     ,OffsetY=0     ,AdvanceX=10   ,Letter="l" },
  { Id=109    ,X=103   ,Y=255   ,Width=35    ,Height=25    ,OffsetX=2     ,OffsetY=8     ,AdvanceX=30   ,Letter="m" },
  { Id=110    ,X=225   ,Y=255   ,Width=25    ,Height=25    ,OffsetX=2     ,OffsetY=8     ,AdvanceX=20   ,Letter="n" },
  { Id=111    ,X=252   ,Y=255   ,Width=25    ,Height=25    ,OffsetX=2     ,OffsetY=8     ,AdvanceX=20   ,Letter="o" },
  { Id=112    ,X=234   ,Y=150   ,Width=27    ,Height=33    ,OffsetX=2     ,OffsetY=8     ,AdvanceX=22   ,Letter="p" },
  { Id=113    ,X=2     ,Y=185   ,Width=27    ,Height=33    ,OffsetX=2     ,OffsetY=8     ,AdvanceX=22   ,Letter="q" },
  { Id=114    ,X=106   ,Y=286   ,Width=21    ,Height=25    ,OffsetX=2     ,OffsetY=8     ,AdvanceX=16   ,Letter="r" },
  { Id=115    ,X=129   ,Y=286   ,Width=21    ,Height=25    ,OffsetX=2     ,OffsetY=8     ,AdvanceX=16   ,Letter="s" },
  { Id=116    ,X=197   ,Y=220   ,Width=23    ,Height=31    ,OffsetX=0     ,OffsetY=2     ,AdvanceX=16   ,Letter="t" },
  { Id=117    ,X=2     ,Y=286   ,Width=25    ,Height=25    ,OffsetX=2     ,OffsetY=8     ,AdvanceX=20   ,Letter="u" },
  { Id=118    ,X=169   ,Y=255   ,Width=27    ,Height=25    ,OffsetX=0     ,OffsetY=8     ,AdvanceX=20   ,Letter="v" },
  { Id=119    ,X=64    ,Y=255   ,Width=37    ,Height=25    ,OffsetX=0     ,OffsetY=8     ,AdvanceX=30   ,Letter="w" },
  { Id=120    ,X=29    ,Y=286   ,Width=25    ,Height=25    ,OffsetX=2     ,OffsetY=8     ,AdvanceX=20   ,Letter="x" },
  { Id=121    ,X=188   ,Y=115   ,Width=29    ,Height=33    ,OffsetX=0     ,OffsetY=8     ,AdvanceX=22   ,Letter="y" },
  { Id=122    ,X=81    ,Y=286   ,Width=23    ,Height=25    ,OffsetX=2     ,OffsetY=8     ,AdvanceX=18   ,Letter="z" },
  { Id=123    ,X=38    ,Y=2     ,Width=21    ,Height=37    ,OffsetX=-2    ,OffsetY=0     ,AdvanceX=12   ,Letter="{" },
  { Id=124    ,X=23    ,Y=2     ,Width=13    ,Height=39    ,OffsetX=2     ,OffsetY=0     ,AdvanceX=8    ,Letter="|" },
  { Id=125    ,X=61    ,Y=2     ,Width=21    ,Height=37    ,OffsetX=0     ,OffsetY=0     ,AdvanceX=14   ,Letter="}" },
  { Id=126    ,X=34    ,Y=313   ,Width=27    ,Height=17    ,OffsetX=0     ,OffsetY=12    ,AdvanceX=20   ,Letter="~" },
}