{-# LANGUAGE OverloadedStrings #-} -- For HTML literals

module Dropline.Server (serve) where

import Dropline.Tracker (Statuses, Status(..))
import Data.Time.Clock.POSIX (POSIXTime, getPOSIXTime)
import Dropline.Wifi (RSSI(..))
import Control.Concurrent.STM (TVar, readTVar, atomically)
import Happstack.Server (Response)
import Happstack.Server.Routing (dir)
import Happstack.Server.SimpleHTTP (ServerPart,
    simpleHTTP, nullConf, port, toResponse, ok)
import Text.Blaze.Html5 as H (html, head, title, body, p, h1, (!))
import Text.Blaze.Html5.Attributes as A (style)
import Control.Applicative ((<|>))
import Control.Monad.Trans (liftIO)
import Data.Map.Strict (elems)
import Data.List (sort)

serve :: TVar Statuses -> IO ()
serve signals = do
    let conf = nullConf { port = 80 }
    let rssis = process signals
    simpleHTTP conf (raw rssis <|> friendly rssis)

raw :: ServerPart [(RSSI, POSIXTime)] -> ServerPart Response
raw rssis = dir "raw" $ do
    signalData <- rssis
    ok $ toResponse $ show $ sort signalData

friendly :: ServerPart [(RSSI, POSIXTime)] -> ServerPart Response
friendly rssis = do
    signalData <- rssis
    let busyScore = round $ sum $ map score signalData
    let busyness | busyScore < 20  = "Not busy"
                 | busyScore < 50  = "A little busy"
                 | busyScore < 100 = "Busy"
                 | otherwise       = "Very busy"
    ok $ toResponse $ H.html $ do
        H.head $ do
            H.title "Dropline busy-o-meter"
        H.body $ do
            let center x = x ! A.style "text-align:center"
            center $ H.p  $ "It is"
            center $ H.h1 $ busyness

process :: TVar Statuses -> ServerPart [(RSSI, POSIXTime)]
process signals = do
    signals' <- liftIO . atomically . readTVar $ signals
    time <- liftIO getPOSIXTime
    let format (Status rssi firstSeen lastSeen) = (rssi, time - firstSeen)
    return $ map format $ elems signals'

score :: (RSSI, POSIXTime) -> Double
-- This algorithm depends entirely on your wifi card and environment.
score (RSSI signal, duration) = timeScore * signalScore / 7 
    where
    -- Starts to ignore signals around 2 or more hours old
    timeScore :: Double
    timeScore = (1/) . (1+) . exp . (/200) $ realToFrac (duration - 2*60*60)
    -- Starts to ignore signals below around 50 dBm
    signalScore :: Double
    signalScore = (1/) . (1+) . exp . (/10) $ realToFrac (negate signal - 50)