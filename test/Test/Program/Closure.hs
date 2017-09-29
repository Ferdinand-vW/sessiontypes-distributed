{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE RebindableSyntax #-}
{-# LANGUAGE TemplateHaskell #-}
module Test.Program.Closure where

import Control.SessionTypes.Indexed
import Control.Distributed.Session
import Control.Distributed.Process as P (Process, ProcessId, NodeId, ReceivePort)
import Control.Distributed.Process.Serializable (SerializableDict(..))
import Control.Distributed.Process.Closure (remotable, mkStatic, mkStaticClosure, mkClosure)

import qualified Prelude as PL

sess1 :: Session ('Cap '[] (R (Int :?> Sel '[V, Wk Eps]))) ('Cap '[] Eps) Int
sess1 = recurseFix $ \f -> do
  n <- recv
  liftIO (putStrLn $ show n)
  if n > 0
    then sel1 >> f
    else selN2 >> weaken0 >> eps n

sess1' :: ProcessId -> Session ('Cap '[] (R (Int :?> Sel '[V, Wk Eps]))) ('Cap '[] Eps) ()
sess1' pid = recurseFix $ \f -> do
  n <- recv
  liftIO (putStrLn $ show n)
  if n > 0
    then sel1 >> f
    else selN2 >> weaken0 >> utsend pid n >> eps ()

sess2 :: Session ('Cap '[] (R (Int :!> Off '[V, Wk Eps]))) ('Cap '[] Eps) ()
sess2 = recurse $ go 3
    where 
      go n = do
        send n
        offer (var $ go (n - 1)) (weaken0 >> eps0)

sessReturn :: Session s s Int
sessReturn = return 5

sessSpawnCh :: ProcessId -> ReceivePort Int -> Session s s ()
sessSpawnCh pid rp = do
  a <- receiveChan rp
  utsend pid a

sessSpawn :: ProcessId -> Session s s ()
sessSpawn pid = utsend pid (5 :: Int)

spawnSess :: SpawnSession Int ()
spawnSess = SpawnSession sess1 sess2

spawnSess0 :: ProcessId -> SpawnSession () ()
spawnSess0 pid = SpawnSession (sess1' pid) sess2

sessWrap :: SessionWrap Int
sessWrap = SessionWrap sessReturn

spawnChWrap :: ProcessId -> ReceivePort Int -> SessionWrap ()
spawnChWrap pid rp = SessionWrap  $ sessSpawnCh pid rp

sessSpawnWrap :: ProcessId -> SessionWrap ()
sessSpawnWrap pid = SessionWrap $ sessSpawn pid

sdictInt :: SerializableDict Int
sdictInt = SerializableDict

remotable ['spawnSess, 'spawnSess0, 'sdictInt, 'sessWrap, 'spawnChWrap, 'sessSpawnWrap]

