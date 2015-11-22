-- -*- coding: utf-8 -*-

--   Copyright (c) 2010-2014, MIT Probabilistic Computing Project
--
--   Licensed under the Apache License, Version 2.0 (the "License");
--   you may not use this file except in compliance with the License.
--   You may obtain a copy of the License at
--
--       http://www.apache.org/licenses/LICENSE-2.0
--
--   Unless required by applicable law or agreed to in writing, software
--   distributed under the License is distributed on an "AS IS" BASIS,
--   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
--   See the License for the specific language governing permissions and
--   limitations under the License.

module DPMMTest where

import Data.RVar (sampleRVar)
import Data.Random
import Data.Random.Distribution.Bernoulli
import Control.Monad

import Utils
import DPMM

type LogDensity a = a -> Double
type Assessable a = (RVar a, LogDensity a)
type TailAssessable a = RVar (Assessable a)

mixture_density :: [LogDensity a] -> LogDensity a
mixture_density ds x = logsumexp (map ($ x) ds) - log (fromIntegral $ length ds)

-- This is a mixture of two Gaussians (-3/1 and 3/1).
two_modes :: Assessable Double
two_modes = (sample, logd) where
    sample = do
      pos_mode <- bernoulli (0.5 :: Double)
      if pos_mode then
          normal 3 1
      else
          normal (-3) 1
    logd x = logsumexp [logPdf (Normal 3 1) x, logPdf (Normal (-3) 1) x] - log 2

two_modes_ta :: TailAssessable Double
two_modes_ta = do
  pos_mode <- bernoulli (0.5 :: Double)
  if pos_mode then
      return $ gaussian 3 1
  else
      return $ gaussian (-3) 1

gaussian :: Double -> Double -> Assessable Double
gaussian mu sig = (normal mu sig, logPdf (Normal mu sig))

estimate_KL :: Assessable a -> LogDensity a -> Int -> RVar Double
estimate_KL from to sample_ct = do
  input <- replicateM sample_ct (fst from)
  return $ (sum $ map term input) / (fromIntegral $ length input)
    where term x = (snd from) x - to x

approximately_assess :: Int -> TailAssessable a -> RVar (LogDensity a)
approximately_assess ct dist = do
  assessors <- liftM (map snd) $ replicateM ct dist
  return $ mixture_density assessors

estimate_KL_ta :: Assessable a -> TailAssessable a -> Int -> Int -> RVar Double
estimate_KL_ta from to latents_ct sample_ct = do
  density <- approximately_assess latents_ct to
  estimate_KL from density sample_ct

dpmm_dist :: DPMM -> Assessable Double
dpmm_dist dpmm = (return $ error "What?", predictive_logdensity dpmm)

trained_dpmm :: [Double] -> Int -> TailAssessable Double
trained_dpmm input iters = liftM dpmm_dist $ train_dpmm input iters

measure_dpmm_kl :: Assessable Double -> Int -> Int -> Int -> Int -> RVar Double
measure_dpmm_kl data_gen train_data_ct iter_ct chain_ct test_ct = do
  input <- replicateM train_data_ct (fst data_gen)
  estimate_KL_ta data_gen (trained_dpmm input iter_ct) chain_ct test_ct

sampleIO :: RVar a -> IO a
sampleIO = sampleRVar