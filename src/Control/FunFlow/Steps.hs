{-# LANGUAGE Arrows              #-}
{-# LANGUAGE GADTs               #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TupleSections       #-}

module Control.FunFlow.Steps where

import           Control.Arrow
import           Control.Arrow.Free   (catch)
import           Control.Exception    (Exception)
import           Control.FunFlow.Base
import           Control.Monad.Catch  (throwM)
import           Data.Store
import           GHC.Conc             (threadDelay)
import           System.Directory
import           System.Random

promptFor :: Read a => Flow eff ex String a
promptFor = proc s -> do
     () <- step putStr -< (s++"> ")
     s' <- step (const getLine) -< ()
     returnA -< read s'

printS :: Show a => Flow eff ex a ()
printS = step $ \s-> print s

failStep :: Flow eff ex () ()
failStep = step $ \_ -> fail "failStep"

worstBernoulli :: Exception ex => (String -> ex) -> Flow eff ex Double Double
worstBernoulli errorC = step $ \p -> do
  r <- randomRIO (0,1)
  if r < p
    then return r
    else throwM . errorC $ "worstBernoulli fail with "++ show r++ " > "++show p

-- | pause for a given number of seconds. Thread through a value to ensure
--   delay does not happen inparallel with other processing
pauseWith :: Store a => Flow eff ex (Int, a) a
pauseWith = step $ \(secs,a) -> do
  threadDelay (secs*1000000)
  return a

-- | on first invocation die and leave a suicide note
--   on second invocation it is resurrected and destroys suicide note, returning contents
melancholicLazarus :: Flow eff ex String String
melancholicLazarus = step $ \s -> do
  let fnm = "/tmp/lazarus_note"
  ex <- doesFileExist fnm
  if ex
    then do s1 <- readFile fnm
            removeFile fnm
            return s1
    else do writeFile fnm s
            fail "lazarus fail"

-- | `retry n s f` reruns `f` on failure at most n times with a delay of `s`
--   seconds between retries
retry :: forall eff ex a b. (Exception ex, Store a)
      => Int -> Int -> Flow eff ex a b -> Flow eff ex a b
retry 0 _ f = f
retry n secs f = catch f $ proc (x, (_ :: ex)) -> do
  x1 <- pauseWith -< (secs,x)
  x2 <- retry (n-1) secs f -< x1
  returnA -< x2
