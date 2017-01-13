// $legal:629:
//
// Copyright 2016 Michael Lowell Roberts & Microsoft Research
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
//,$

module Flutterbye.Concurrency.Linearize
open FStar.Seq
open Flutterbye.Seq
open Flutterbye.Concurrency.Thread

val is_fresh:
      #state_t:Type
   -> ops:ops_t state_t
   -> state_t
   -> transaction_t ops
   -> Tot bool
let is_fresh #state_t ops state txn =
   txn.observation = state

val linearize_step_loop:
      state_t:Type
   -> ops:ops_t state_t
   -> pending:seq (transaction_t ops)
   -> accum:thread_t ops{
            contains_p (is_Commit) accum.steps
         \/ contains_p (is_fresh ops accum.state) pending
      }
   -> Tot (accum':thread_t ops{contains_p (is_Commit) accum'.steps})
      (decreases (length pending))
let rec linearize_step_loop state_t ops pending accum =
   if 0 = length pending then
      accum
   else begin
      let i = 0 in
      let picked = index pending i in
      if picked.observation = accum.state then begin
         // if the picked transaction is fresh, we can commit it.
         let step' = Commit picked in
         let state' = apply_op ops picked.opcode accum.state in
         let steps' = append accum.steps (create 1 step') in
         let pending' = remove pending i in
         let accum' = { state = state'; steps = steps' } in
         Flutterbye.Seq.Contains.create_lemma 1 step';
         assert (contains_p (is_Commit) (create 1 step'));
         Flutterbye.Seq.Contains.append_lemma accum.steps (create 1 step');
         assert (contains_p (is_Commit) steps');
         linearize_step_loop state_t ops pending' accum'
      end
      else begin
         // otherwise, we mark the transaction as stale.
         let step' = Stale picked in
         let steps' = append accum.steps (create 1 step') in
         let pending' = remove pending i in
         let accum' = { state = accum.state; steps = steps' } in
         Flutterbye.Seq.Contains.append_lemma accum.steps (create 1 step');
         assert (contains_p (is_Commit) accum.steps <==> contains_p (is_Commit)  steps');
         Flutterbye.Seq.Contains.remove_lemma pending i (is_fresh ops accum.state);
         assert (contains_p (is_fresh ops accum.state) pending ==> contains_p (is_fresh ops accum.state) pending');
         linearize_step_loop state_t ops pending' accum'
      end
   end

val linearize_step:
      state_t:Type
   -> ops:ops_t state_t
   -> pending:seq (transaction_t ops)
   -> state:state_t{contains_p (is_fresh ops state) pending}
   -> Tot (thread':(thread_t ops){contains_p (is_Commit) thread'.steps})
      (decreases (length pending))
let linearize_step state_t ops pending state =
   let thread = { state = state; steps = createEmpty } in
   linearize_step_loop state_t ops pending thread
