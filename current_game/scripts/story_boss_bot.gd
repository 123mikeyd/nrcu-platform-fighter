extends "res://scripts/bot_controller.gd"
# Candidate-only boss intent driver. No changes to preserved moves/damage/forms.
var form_clock=0.0
var switch_hold=0.0
var switch_release=0.0
func read(fighter:Node3D,delta:float)->Dictionary:
 var base=super.read(fighter,delta).duplicate()
 form_clock+=delta
 if form_clock>8.0 and switch_release<=0 and switch_hold<=0 and fighter.is_grounded() and fighter.attack_cooldown<=0 and fighter.hitstun<=0 and fighter.mephisto_moves.move.is_empty():
  form_clock=0.0;switch_release=.12;switch_hold=.24
 # A release edge is required if the generic bot was already holding special.
 # Emit ordinary intents, never mutate the preserved boss's lead state.
 if switch_release>0:
  switch_release=maxf(0,switch_release-delta)
  return {"left":false,"right":false,"up":false,"down":false,"jump":false,"attack":false,"special":false,"shield":false}
 if switch_hold>0:
  switch_hold=maxf(0,switch_hold-delta)
  return {"left":false,"right":false,"up":false,"down":true,"jump":false,"attack":false,"special":true,"shield":false}
 # Give neutral magic/spray a turn rather than only horizontal special attacks.
 if base.special and not base.up and not base.down and sequence%2==0:
  base.left=false;base.right=false
 return base
func reset():
 super.reset();form_clock=0.0;switch_hold=0.0;switch_release=0.0
