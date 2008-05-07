-----------------------------------------------------------------------------
-- |
-- Module      :  Graphics.Rendering.Chart.Axis
-- Copyright   :  (c) Tim Docker 2006
-- License     :  BSD-style (see chart/COPYRIGHT)

module Graphics.Rendering.Chart.Axis where

import qualified Graphics.Rendering.Cairo as C
import System.Time
import System.Locale (defaultTimeLocale)
import Control.Monad
import Data.List

import Graphics.Rendering.Chart.Types
import Graphics.Rendering.Chart.Renderable

-- | The concrete data type for an axis
data Axis =  Axis {
		   
    -- | The axis_viewport function maps values into device
    -- cordinates.
    axis_viewport :: Range -> Double -> Double,

    -- | The title string to be displayed on the axis. An
    -- empty string means no title.
    axis_title :: String,

    -- | The tick marks on the axis as pairs.
    -- The first element is the position on the axis
    -- (in viewport units) and the second element is the
    -- length of the tick in output coordinates.
    -- The tick starts on the axis, and positive number are drawn
    -- towards the plot area.
    axis_ticks :: [(Double,Double)],
    
    -- | The labels on an axis as pairs. The first element 
    -- is the position on the axis (in viewport units) and
    -- the second is the label text string.
    axis_labels :: [ (Double, String) ],

    -- | The positions on the axis (in viewport units) where
    -- we want to show grid lines.
    axis_grid :: [ Double ],

    -- | How far the labels are to be drawn from the axis.
    axis_label_gap :: Double,

    axis_title_style :: CairoFontStyle,
    axis_line_style :: CairoLineStyle,
    axis_label_style :: CairoFontStyle,
    axis_grid_style :: CairoLineStyle

}

-- | Function type to generate an optional axis given a set
-- of points to be plotted against that axis.
type AxisFn = [Double] -> Maybe Axis

-- | Function type to generate a pair of axes (either top 
-- and bottom, or left and right), given the set of points to
-- be plotted against each of them.
type AxesFn = [Double] -> [Double] -> (Maybe Axis,Maybe Axis)

data AxisT = AxisT RectEdge Axis

instance ToRenderable AxisT where
  toRenderable at = Renderable {
     minsize=minsizeAxis at,
     render=renderAxis at
  }

minsizeAxis :: AxisT -> CRender RectSize
minsizeAxis (AxisT at a) = do
    let labels = map snd (axis_labels a)
    c $ C.save
    setFontStyle (axis_label_style a)
    labelSizes <- mapM textSize labels
    c $ C.restore
    let (lw,lh) = foldl maxsz (0,0) labelSizes
    let ag = axis_label_gap a
    let tsize = maximum [ max 0 (-l) | (v,l) <- axis_ticks a ]
    let sz = case at of
		     E_Top    -> (lw,max (lh + ag) tsize)
		     E_Bottom -> (lw,max (lh + ag) tsize)
		     E_Left   -> (max (lw + ag) tsize, lh)
		     E_Right  -> (max (lw + ag) tsize, lh)
    return sz

  where
    maxsz (w1,h1) (w2,h2) = (max w1 w2, max h1 h2)


-- | Calculate the amount by which the labels extend beyond
-- the ends of the axis
axisOverhang :: AxisT -> CRender (Double,Double)
axisOverhang (AxisT at a) = do
    let labels = map snd (sort (axis_labels a))
    c $ C.save
    setFontStyle (axis_label_style a)
    labelSizes <- mapM textSize labels
    c $ C.restore
    case labelSizes of
        [] -> return (0,0)
	ls  -> let l1 = head ls
		   l2 = last ls
		   ohangv = return (snd l1 / 2, snd l2 / 2)
		   ohangh = return (fst l1 / 2, fst l2 / 2)
		   in
		   case at of
		       E_Top -> ohangh
		       E_Bottom -> ohangh
		       E_Left -> ohangv
		       E_Right -> ohangh

renderAxis :: AxisT -> Rect -> CRender ()
renderAxis at@(AxisT et a) rect = do
   c $ C.save
   setLineStyle (axis_line_style a)
   strokeLines [Point sx sy,Point ex ey]
   mapM_ drawTick (axis_ticks a)
   c $ C.restore
   c $ C.save
   setFontStyle (axis_label_style a)
   mapM_ drawLabel (axis_labels a)
   c $ C.restore
 where
   (sx,sy,ex,ey,tp,axisPoint) = axisMapping at rect

   drawTick (value,length) = 
       let t1 = axisPoint value
	   t2 = t1 `pvadd` (vscale length tp)
       in strokeLines [t1,t2]

   (hta,vta,lp) = 
       let g = axis_label_gap a
       in case et of
		  E_Top    -> (HTA_Centre,VTA_Bottom,(Vector 0 (-g)))
		  E_Bottom -> (HTA_Centre,VTA_Top,(Vector 0 g))
		  E_Left   -> (HTA_Right,VTA_Centre,(Vector (-g) 0))
		  E_Right  -> (HTA_Left,VTA_Centre,(Vector g 0))

   drawLabel (value,s) = do
       drawText hta vta (axisPoint value `pvadd` lp) s

axisMapping :: AxisT -> Rect -> (Double,Double,Double,Double,Vector,Double->Point)
axisMapping (AxisT et a) rect = case et of
    E_Top    -> (x1,y2,x2,y2, (Vector 0 1),    mapx (x1,x2) y2) 
    E_Bottom -> (x1,y1,x2,y1, (Vector 0 (-1)), mapx (x1,x2) y1)
    E_Left   -> (x2,y2,x2,y1, (Vector (1) 0),  mapy (y1,y2) x2)		
    E_Right  -> (x1,y2,x1,y1, (Vector (-1) 0), mapy (y1,y2) x1)
  where
    (Rect (Point x1 y1) (Point x2 y2)) = rect

    mapx :: Range -> Double -> Double -> Point
    mapx xr y x = Point (axis_viewport a xr x) y

    mapy :: Range -> Double -> Double -> Point
    mapy (yr0,yr1) x y = Point x (axis_viewport a (yr1,yr0) y)

renderAxisGrid :: Rect -> AxisT -> CRender ()
renderAxisGrid rect@(Rect p1 p2) at@(AxisT re a) = do
    c $ C.save
    setLineStyle (axis_grid_style a)
    mapM_ (drawGridLine re) (axis_grid a)
    c $ C.restore
  where
    (sx,sy,ex,ey,tp,axisPoint) = axisMapping at rect

    drawGridLine E_Top = vline
    drawGridLine E_Bottom = vline
    drawGridLine E_Left = hline
    drawGridLine E_Right = hline

    vline v = let v' = p_x (axisPoint v)
	      in strokeLines [Point v' (p_y p1),Point v' (p_y p2)]

    hline v = let v' = p_y (axisPoint v)
	      in strokeLines [Point (p_x p1) v',Point (p_x p2) v']

----------------------------------------------------------------------

steps:: Double -> Range -> [Rational]
steps nSteps (min,max) = [ (fromIntegral (min' + i)) * s | i <- [0..n] ]
  where
    min' = floor (min / fromRational s)
    max' = ceiling (max / fromRational s)
    n = (max' - min')
    s = chooseStep nSteps (min,max)

chooseStep :: Double -> Range -> Rational
chooseStep nsteps (min,max) = s
  where
    mult = 10 ^^ (floor ((log (max-min) - log nsteps) / log 10))
    steps = map (mult*) [0.1, 0.2, 0.25, 0.5, 1.0, 2.0, 2.5, 5.0, 10, 20, 25, 50]
    steps' =  sort [ (abs((max-min)/(fromRational s) - nsteps), s) | s <- steps ]
    s = snd (head steps')

-- | Explicitly specify an axis
explicitAxis :: Maybe Axis -> AxisFn
explicitAxis ma _ = ma

linearTicks r = (major, minor)
 where
  major = steps 5 r
  minor = steps 50 (fromRational (minimum major),fromRational (maximum major))

autoAxis labelf transform (rlabelvs, rtickvs) a = Just axis
  where
    axis =  a {
        axis_viewport=newViewport,
	axis_ticks=newTicks,
	axis_grid=gridvs,
	axis_labels=newLabels
	}
    newViewport = transform (min',max')
    newTicks = [ (v,2) | v <- tickvs ] ++ [ (v,5) | v <- labelvs ] 
    newLabels = [(v,labelf v) | v <- labelvs]
    labelvs = map fromRational rlabelvs
    tickvs = map fromRational rtickvs
    min' = minimum labelvs
    max' = maximum labelvs

    gridvs = case (axis_grid a) of 
       [] -> []
       _  -> labelvs

-- | Generate a linear axis automatically.
-- The supplied axis is used as a template, with the viewport, ticks, labels
-- and grid set appropriately for the data displayed against that axies.
-- The resulting axis will only show a grid if the template has some grid
-- values.
autoScaledAxis' :: (Double->String) -> Axis -> AxisFn
autoScaledAxis' labelf a ps0 = autoAxis labelf vmap (linearTicks (range ps)) a
  where
    ps = filter isValidNumber ps0
    (min,max) = (minimum ps,maximum ps)
    range [] = (0,1)
    range _  | min == max = (min-0.5,min+0.5)
	     | otherwise = (min,max)

-- | Generate a linear axis automatically.
-- Same as autoScaledAxis', but with labels generated with "showD"
-- (showD is show for doubles, but with any trailing ".0" removed)
autoScaledAxis :: Axis -> AxisFn
autoScaledAxis = autoScaledAxis' showD

showD x = case reverse $ show x of
            '0':'.':r -> reverse r
            _ -> show x
    

log10 :: (Floating a) => a -> a
log10 = logBase 10

frac x | 0 <= b = (a,b)
       | otherwise = (a-1,b+1)
 where
  (a,b) = properFraction x

lmap (x1,x2) r x = vmap (log x1, log x2) r (log x)

{- 
 Rules: Do no subdivide between powers of 10 until all powers of 10
          get a major ticks.
        Do not subdivide between powers of ten as [1,2,4,6,8,10] when
          5 gets a major ticks 
          (ie the major ticks need to be a subset of the minor tick)
-}
logTicks :: Range -> ([Rational],[Rational])
logTicks (low,high) = (major,minor)
 where
  ratio = high/low
  lower a l = let (i,r) = frac (log10 a) in
            (maximum (1:(filter (\x -> log10 (fromRational x) <= r) l)))*10^^i
  upper a l = let (i,r) = properFraction (log10 a) in
            (minimum (10:(filter (\x -> r <= log10 (fromRational x)) l)))*10^^i
  inRange (a,b) l x = (lower a l <= x) && (x <= upper b l)
  powers :: (Double,Double) -> [Rational] -> [Rational]
  powers (x,y) l = [a*10^^p | p<-[(floor (log10 x))..(ceiling (log10 y))], a<-l]
  midselection r l = filter (inRange r l) (powers r l)
  major | 17.5 < log10 ratio = map (\x -> 10^^(round x)) $
                         steps (min 5 (log10 ratio)) (log10 low, log10 high)
        | 12 < log10 ratio = map (\x -> 10^^(round x)) $
                         steps ((log10 ratio)/5) (log10 low, log10 high)
        | 6 < log10 ratio = map (\x -> 10^^(round x)) $
                         steps ((log10 ratio)/2) (log10 low, log10 high)
        | 3 < log10 ratio = midselection (low,high) [1,10]
        | 20 < ratio = midselection (low,high) [1,5,10]
        | 6 < ratio = midselection (low,high) [1,2,4,6,8,10]
        | 3 < ratio = midselection (low,high) [1..10]
        | otherwise = steps 5 (low,high)
  (l',h') = (minimum major, maximum major)
  (dl',dh') = (fromRational l', fromRational h')
  ratio' = fromRational (h'/l')
  minor | 50 < log10 ratio' = map (\x -> 10^^(round x)) $
                              steps 50 (log10 $ dl', log10 $ dh')
        | 6 < log10 ratio' = filter (\x -> l'<=x && x <=h') $
                             powers (dl', dh') [1,10]
        | 3 < log10 ratio' = filter (\x -> l'<=x && x <=h') $
                             powers (dl',dh') [1,5,10]
        | 6 < ratio' = filter (\x -> l'<=x && x <=h') $ 
                       powers (dl',dh') [1..10]
        | 3 < ratio' = filter (\x -> l'<=x && x <=h') $ 
                       powers (dl',dh') [1,1.2..10]
        | otherwise = steps 50 (dl', dh')

-- | Generate a log axis automatically.
-- The supplied axis is used as a template, with the viewport, ticks, labels
-- and grid set appropriately for the data displayed against that axies.
-- The resulting axis will only show a grid if the template has some grid
-- values.
autoScaledLogAxis' :: (Double->String) -> Axis -> AxisFn
autoScaledLogAxis' labelf a ps0 = autoAxis labelf lmap (logTicks (range ps)) a
  where
    ps = filter isValidNumber ps0
    (min, max) = (minimum ps,maximum ps)
    range [] = (3,30)
    range _  | min == max = (min/3,max*3)
	     | otherwise = (min,max)

-- | Generate a log axis automatically.
-- Same as autoScaledLogAxis', but with labels generated with "showD"
-- (showD is show for doubles, but with any trailing ".0" removed)
autoScaledLogAxis :: Axis -> AxisFn
autoScaledLogAxis = autoScaledLogAxis' showD

-- | Show independent axes on each side of the layout
independentAxes :: AxisFn -> AxisFn -> AxesFn
independentAxes af1 af2 pts1 pts2 = (af1 pts1, af2 pts2)

-- | Show the same axis on both sides of the layout
linkedAxes :: AxisFn -> AxesFn
linkedAxes af pts1 pts2 = (a,a)
  where
    a = af (pts1++pts2)

-- | Show the same axis on both sides of the layout, but with labels
-- only on the primary side
linkedAxes' :: AxisFn -> AxesFn
linkedAxes' af pts1 pts2 = (a,removeLabels a)
  where
    a  = af (pts1++pts2)
    removeLabels = liftM (\a -> a{axis_title="",axis_labels = []})

----------------------------------------------------------------------

defaultAxisLineStyle = solidLine 1 black
defaultGridLineStyle = dashedLine 1 [5,5] grey8

defaultAxis = Axis {
    axis_viewport = vmap (0,1),
    axis_title = "",
    axis_ticks = [(0,10),(1,10)],
    axis_labels = [],
    axis_grid = [0.0,0.5,1.0],
    axis_label_gap = 10,
    axis_title_style = defaultFontStyle,
    axis_line_style = defaultAxisLineStyle,
    axis_label_style = defaultFontStyle,
    axis_grid_style = defaultGridLineStyle
}

----------------------------------------------------------------------

refClockTime = toClockTime CalendarTime {
    ctYear=2000,
    ctMonth=toEnum 0,
    ctDay=1,
    ctHour=0,
    ctMin=0,
    ctSec=0,
    ctPicosec=0,
    ctTZ=0,
    ctWDay=Saturday,
    ctYDay=0,
    ctTZName="",
    ctIsDST=False
    }

-- | Map a clocktime value to a plot cordinate
doubleFromClockTime :: ClockTime -> Double
doubleFromClockTime ct = fromIntegral (tdSec (diffClockTimes ct refClockTime))

-- | Map a plot cordinate to a clocktime
clockTimeFromDouble :: Double -> ClockTime
clockTimeFromDouble v = (addToClockTime tdiff refClockTime)
  where
    tdiff = TimeDiff {
       tdYear = 0,
       tdMonth = 0,
       tdDay = 0,
       tdHour = 0,
       tdMin = 0,
       tdSec = floor v,
       tdPicosec = 0
    }

-- | TimeSeq is a (potentially infinite) set of times. When passes
-- a reference time, the function returns a a pair of lists. The first
-- contains all times in the set less than the reference time in
-- decreasing order. The second contains all times in the set greater
-- than or equal to the reference time, in increasing order.
type TimeSeq = ClockTime-> ([ClockTime],[ClockTime])

coverTS tseq min max = min' ++ enumerateTS tseq min max ++ max'
  where
    min' =  if elemTS min tseq then [] else take 1 (fst (tseq min))
    max' =  if elemTS max tseq then [] else take 1 (snd (tseq max))

enumerateTS tseq min max = reverse (takeWhile (>=min) ts1)  ++ takeWhile (<=max) ts2
  where
    (ts1,ts2) = tseq min

elemTS t tseq = case tseq t of
    (_,(t0:_)) | t == t0 -> True
    _                    -> False

-- | How to display a time
type TimeLabelFn = ClockTime -> String

-- | Use an strftime() formatted string to display a time
formatTime :: String -> TimeLabelFn
formatTime s t =  formatCalendarTime defaultTimeLocale s (toUTCTime t)

-- | Create an 'AxisFn' to for a time axis. The first 'TimeSeq' sets the minor ticks,
-- and the ultimate range will aligned to it's elements. The second 'TimeSeq' sets
-- the labels and grid. The 'TimeLabelFn' is used to format clocktimes for labels.
-- The values to be plotted against this axis can be created with 'doubleFromClockTime'
timeAxis :: TimeSeq -> TimeSeq -> TimeLabelFn -> Axis -> AxisFn
timeAxis tseq lseq labelf a pts = Just axis
  where
    axis =  a {
        axis_viewport=vmap (dfct min', dfct max'),
	axis_ticks=[ (dfct t,2) | t <- times] ++ [ (t,5) | t <- ltimes', visible t],
	axis_labels=[ (t,l) | (t,l) <- labels, visible t],
	axis_grid=[ t | t <- ltimes', visible t]
	}
    (min,max) = case pts of
		[] -> (refClockTime,refClockTime)
		ps -> let min = minimum ps
			  max = maximum ps in
			  (ctfd min,ctfd max)

    times = coverTS tseq min max
    ltimes = coverTS lseq min max
    ltimes' = map dfct ltimes
    min' = minimum times
    max' = maximum times
    visible t = dfct min' <= t && t <= dfct max'
    labels = [ ((dfct m2 + dfct m1) / 2, labelf m1) | (m1,m2) <- zip ltimes (tail ltimes) ]
    dfct = doubleFromClockTime
    ctfd = clockTimeFromDouble

-- | A 'TimeSeq' for calendar days
days :: TimeSeq
days t = (iterate rev t1, tail (iterate fwd t1))
  where t0 = (toClockTime.zeroTime.toUTCTime) t
        t1 = if t0 < t then t0 else (rev t0)
        rev = addToClockTime noTimeDiff{tdDay=(-1)}
        fwd = addToClockTime noTimeDiff{tdDay=1}

-- | A 'TimeSeq' for calendar months
months :: TimeSeq
months t = (iterate rev t1, tail (iterate fwd t1))
  where t0 = (toClockTime.(\t -> t{ctDay=1}).zeroTime.toUTCTime) t
        t1 = if t0 < t then t0 else (rev t0)
        rev = addToClockTime noTimeDiff{tdMonth=(-1)}
        fwd = addToClockTime noTimeDiff{tdMonth=1}

-- | A 'TimeSeq' for calendar years
years :: TimeSeq
years t = (iterate rev t1, tail (iterate fwd t1))
  where t0 = (toClockTime.(\t -> t{ctMonth=January,ctDay=1}).zeroTime.toUTCTime) t
        t1 = if t0 < t then t0 else (rev t0)
        rev = addToClockTime noTimeDiff{tdMonth=(-12)}
        fwd = addToClockTime noTimeDiff{tdMonth=12}

zeroTime t = t{ctHour=0,ctMin=0,ctSec=0,ctPicosec=0}

-- | Automatically choose a suitable time axis, based upon the time range of data.
-- The values to be plotted against this axis can be created with 'doubleFromClockTime'
autoTimeAxis :: Axis -> AxisFn
autoTimeAxis a pts =
    if tdiff < (normalizeTimeDiff noTimeDiff{tdDay=15})
    then  timeAxis days days (formatTime "%d-%b")  a pts
    else if tdiff < (normalizeTimeDiff noTimeDiff{tdMonth=3})
         then timeAxis days months (formatTime "%b-%y") a pts
         else if tdiff < (normalizeTimeDiff noTimeDiff{tdMonth=15})
              then timeAxis months months (formatTime "%b-%y") a pts
              else if tdiff < (normalizeTimeDiff noTimeDiff{tdMonth=60})
                   then timeAxis months years (formatTime "%Y") a pts
                   else timeAxis years years (formatTime "%Y") a pts
  where
    tdiff = normalizeTimeDiff (t1 `diffClockTimes` t0)
    t1 = clockTimeFromDouble (maximum pts)
    t0 = clockTimeFromDouble (minimum pts)

