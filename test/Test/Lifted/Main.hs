{-# LANGUAGE TemplateHaskell #-}
import Control.Distributed.Session (evalSessionEq, sessionRemoteTable, spawnChannel, call, spawn)
import Control.Distributed.Process (Process, NodeId, RemoteTable, liftIO, getSelfPid, sendChan, expect)
import Control.Distributed.Process.Node
import Control.Distributed.Process.Closure
import Network.Transport.TCP

import Test.Hspec
import Test.Program.Closure

main :: IO ()
main = do
  n <- newNode 10010
  runProcess n $ do
    let nid = localNodeId n
    x1 <- test_call nid
    x2 <- test_spawn nid
    x3 <- test_spawnChannel nid

    liftIO $ do
      hspec $ do
        describe "call" $ do
          it "spawns a `Session` on a remote node and waits for its result" $
            x1 `shouldBe` 5

        describe "spawn" $ do
          it "spawns a `Session` on a remote node" $
            x2 `shouldBe` 5

        describe "spawnChannel" $ do
          it "spawns a `Session` on a remote node together with a typed channel" $
            x3 `shouldBe` 6
        
myRemoteTable :: RemoteTable
myRemoteTable = Test.Program.Closure.__remoteTable $ sessionRemoteTable initRemoteTable

newNode p = do
  Right t <- createTransport "127.0.0.1" (show p) (\sn -> ("127.0.0.1", sn)) defaultTCPParameters
  newLocalNode t myRemoteTable

test_call :: NodeId -> Process Int
test_call nid = evalSessionEq $ call $(mkStatic 'sdictInt) nid $(mkStaticClosure 'sessWrap)

test_spawn :: NodeId -> Process Int
test_spawn nid = do
  pid <- getSelfPid
  evalSessionEq $ spawn nid ($(mkClosure 'sessSpawnWrap) pid)
  expect

test_spawnChannel :: NodeId -> Process Int
test_spawnChannel nid = do
  pid <- getSelfPid
  sp <- evalSessionEq $ spawnChannel $(mkStatic 'sdictInt) nid ($(mkClosure 'spawnChWrap) pid)
  sendChan sp 6
  expect