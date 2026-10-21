extends Weapon
class_name RepeaterWeapon

## Sweat Carbine (repeater) trigger: tap to fire.
## A press starts one volley, holding does nothing, and only a full
## release re-arms the next shot. No charge-up, no hold-to-fire.

var armed := true

## True on the frame a fresh tap begins — the gate for hit logic.
func can_fire() -> bool:
	if Input.is_action_just_released("shoot"):
		armed = true
	if armed and Input.is_action_just_pressed("shoot"):
		armed = false
		return true
	return false
