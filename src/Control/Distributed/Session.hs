-- | This package defines a wrapper over the sessiontypes library that allows for evaluating session typed programs to Cloud Haskell programs.
--
-- The goal of this library is to allow a user to define two dual session typed programs, spawn two processes and have these processes evaluate the programs.
--
-- Session types guarantee that the resulting Cloud Haskell programs correctly implement the protocol and that they are non-deadlocking.
--
-- We define a session typed program with an indexed monad `Session` that is both a reader monad and a wrapper over a `STTerm` that uses `Process` as its underlying monad.
-- 
-- This module exports the most important parts of this library:
--
-- * "Control.Distributed.Session.Session": Defines the `Session` monad and `SessionInfo` that is used as the environment of `Session`.
-- * "Control.Distributed.Session.Eval": Defines the interpreter for evaluation a `Session` to a `Process`.
-- * "Control.Distributed.Session.Spawn": Defines several combinators for spawning sessions.
-- * "Control.Distributed.Session.Closure": Module for constructing closures of sessions.
-- * "Control.Distributed.Session.STChannel": Session typed channel that allows for transmitting values of different types.
-- * "Control.Distributed.Session.Lifted": Exports lifted functions from the distributed-process package. 
--
-- Additionally we defined wrappers for using the interpreters defined in the sessiontypes package on a `Session`:
--
-- * "Control.Distributed.Session.Debug"
-- * "Control.Distributed.Session.Interactive"
-- * "Control.Distributed.Session.Normalize"
-- * "Control.Distributed.Session.Visualize"
module Control.Distributed.Session (
  -- * Core
  module Control.SessionTypes,
  -- * Session
  -- ** Data types
  Session(..),
  SessionInfo(..),
  runSession,
  -- ** Lifting
  liftP,
  liftST,
  -- * Spawning sessions
  -- ** Call
  callLocalSessionP,
  callLocalSession,
  callRemoteSessionP,
  callRemoteSession,
  callRemoteSessionP',
  callRemoteSession',
  -- ** Spawn
  spawnLLSessionP,
  spawnLLSession,
  spawnLRSessionP,
  spawnLRSession,
  spawnRRSessionP,
  spawnRRSession,
  -- * Eval
  evalSession,
  evalSessionEq,
  evalSessionEq',
  -- * Closures
  -- ** Encapsulation
  SpawnSession (..),
  SessionWrap (..),
  -- ** RemoteTable
  sessionRemoteTable,
  -- ** Static and Closures
  -- *** Singular
  remoteSessionStatic,
  remoteSessionClosure,
  remoteSessionStatic',
  remoteSessionClosure',
  -- *** SpawnChannel
  spawnChannelStatic,
  spawnChannelClosure,
  -- *** Local Remote Evaluation
  evalLocalSession,
  remoteSpawnSessionStatic,
  remoteSpawnSessionClosure,
  remoteSpawnSessionStatic',
  remoteSpawnSessionClosure',
  -- *** Remote Remote Evaluation
  rrSpawnSessionSendStatic,
  rrSpawnSessionSendClosure,
  rrSpawnSessionExpectStatic,
  rrSpawnSessionExpectClosure,
  -- * STChannel
  -- ** Data types
  Message(..),
  STSendPort(..),
  STReceivePort(..),
  -- ** Type synonyms
  STChan,
  STChanBi,
  UTChan,
  -- ** Create
  newSTChan,
  newSTChanBi,
  newUTChan,
  toSTChan,
  toSTChanBi,
  sendProxy,
  recvProxy,
  -- ** Usage
  sendSTChan,
  recvSTChan,
  STSplit(..),
  STRec(..),
  -- ** Channel transformer
  STChannelT(..),
  sendSTChanM,
  recvSTChanM,
  sel1ChanM,
  sel2ChanM,
  off1ChanM,
  off2ChanM,
  recChanM,
  wkChanM,
  varChanM,
  epsChanM,
  -- * Lifted
  utsend,
  usend,
  expect,
  expectTimeout,
  newChan,
  sendChan,
  receiveChan,
  receiveChanTimeout,
  mergePortsBiased,
  mergePortsRR,
  unsafeSend,
  unsafeSendChan,
  unsafeNSend,
  unsafeNSendRemote,
  receiveWait,
  receiveTimeout,
  unwrapMessage,
  handleMessage,
  handleMessage_,
  handleMessageP,
  handleMessageP_,
  handleMessageIf,
  handleMessageIf_,
  handleMessageIfP,
  handleMessageIfP_,
  forward,
  uforward,
  delegate,
  relay,
  proxy,
  proxyP,
  spawn,
  spawnP,
  call,
  callP,
  terminate,
  die,
  kill,
  exit,
  catchExit,
  catchExitP,
  catchesExit,
  catchesExitP,
  getSelfPid,
  getSelfNode,
  getOthPid,
  getOthNode,
  getProcessInfo,
  getNodeStats,
  link,
  linkNode,
  unlink,
  unlinkNode,
  monitor,
  monitorNode,
  monitorPort,
  unmonitor,
  withMonitor,
  withMonitor_,
  withMonitorP,
  withMonitorP_,
  unStatic,
  unClosure,
  say,
  register,
  unregister,
  whereis,
  nsend,
  registerRemoteAsync,
  reregisterRemoteAsync,
  whereisRemoteAsync,
  nsendRemote,
  spawnAsync,
  spawnAsyncP,
  spawnSupervised,
  spawnSupervisedP,
  spawnLink,
  spawnLinkP,
  spawnMonitor,
  spawnMonitorP,
  spawnChannel,
  spawnChannelP,
  spawnLocal,
  spawnLocalP,
  spawnChannelLocal,
  spawnChannelLocalP,
  callLocal,
  callLocalP,
  reconnect,
  reconnectPort
) where



import Control.SessionTypes

import Control.Distributed.Session.Session (
  Session(..),
  SessionInfo(..),
  runSession,
  liftP,
  liftST
  )

import Control.Distributed.Session.Exception ()

import Control.Distributed.Session.Spawn (
  callLocalSessionP,
  callLocalSession,
  callRemoteSessionP,
  callRemoteSession,
  callRemoteSessionP',
  callRemoteSession',
  spawnLLSessionP,
  spawnLLSession,
  spawnLRSessionP,
  spawnLRSession,
  spawnRRSessionP,
  spawnRRSession
  )

import Control.Distributed.Session.Eval (
  evalSession,
  evalSessionEq,
  evalSessionEq'
  )

import Control.Distributed.Session.Closure (
  SpawnSession (..),
  SessionWrap (..),
  sessionRemoteTable,
  remoteSessionStatic,
  remoteSessionClosure,
  remoteSessionStatic',
  remoteSessionClosure',
  spawnChannelStatic,
  spawnChannelClosure,
  evalLocalSession,
  remoteSpawnSessionStatic,
  remoteSpawnSessionClosure,
  remoteSpawnSessionStatic',
  remoteSpawnSessionClosure',
  rrSpawnSessionSendStatic,
  rrSpawnSessionSendClosure,
  rrSpawnSessionExpectStatic,
  rrSpawnSessionExpectClosure
  )

import Control.Distributed.Session.STChannel (
  Message(..),
  STSendPort(..),
  STReceivePort(..),
  STChan,
  STChanBi,
  UTChan,
  newSTChan,
  newSTChanBi,
  newUTChan,
  toSTChan,
  toSTChanBi,
  sendProxy,
  recvProxy,
  sendSTChan,
  recvSTChan,
  STSplit(..),
  STRec(..),
  STChannelT(..),
  sendSTChanM,
  recvSTChanM,
  sel1ChanM,
  sel2ChanM,
  off1ChanM,
  off2ChanM,
  recChanM,
  wkChanM,
  varChanM,
  epsChanM
  )

import Control.Distributed.Session.Lifted (
  utsend,
  usend,
  expect,
  expectTimeout,
  newChan,
  sendChan,
  receiveChan,
  receiveChanTimeout,
  mergePortsBiased,
  mergePortsRR,
  unsafeSend,
  unsafeSendChan,
  unsafeNSend,
  unsafeNSendRemote,
  receiveWait,
  receiveTimeout,
  unwrapMessage,
  handleMessage,
  handleMessage_,
  handleMessageP,
  handleMessageP_,
  handleMessageIf,
  handleMessageIf_,
  handleMessageIfP,
  handleMessageIfP_,
  forward,
  uforward,
  delegate,
  relay,
  proxy,
  proxyP,
  spawn,
  spawnP,
  call,
  callP,
  terminate,
  die,
  kill,
  exit,
  catchExit,
  catchExitP,
  catchesExit,
  catchesExitP,
  getSelfPid,
  getSelfNode,
  getOthPid,
  getOthNode,
  getProcessInfo,
  getNodeStats,
  link,
  linkNode,
  unlink,
  unlinkNode,
  monitor,
  monitorNode,
  monitorPort,
  unmonitor,
  withMonitor,
  withMonitor_,
  withMonitorP,
  withMonitorP_,
  unStatic,
  unClosure,
  say,
  register,
  unregister,
  whereis,
  nsend,
  registerRemoteAsync,
  reregisterRemoteAsync,
  whereisRemoteAsync,
  nsendRemote,
  spawnAsync,
  spawnAsyncP,
  spawnSupervised,
  spawnSupervisedP,
  spawnLink,
  spawnLinkP,
  spawnMonitor,
  spawnMonitorP,
  spawnChannel,
  spawnChannelP,
  spawnLocal,
  spawnLocalP,
  spawnChannelLocal,
  spawnChannelLocalP,
  callLocal,
  callLocalP,
  reconnect,
  reconnectPort
  )