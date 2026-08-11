class_name AdResult
extends RefCounted

## Rewarded ve interstitial sonuc kodlari ayni kapali sozlesmeyi kullanir.
## EARNED yalnizca rewarded odulunu verir; DISPLAYED interstitial'in basariyla
## gosterilip kapandigini ifade eder.
enum Code {
	EARNED,
	CLOSED_WITHOUT_REWARD,
	DISPLAYED,
	FAILED,
	UNAVAILABLE,
	SKIPPED_POLICY,
}


static func label(code: int) -> StringName:
	match code:
		Code.EARNED:
			return &"earned"
		Code.CLOSED_WITHOUT_REWARD:
			return &"closed_without_reward"
		Code.DISPLAYED:
			return &"displayed"
		Code.FAILED:
			return &"failed"
		Code.UNAVAILABLE:
			return &"unavailable"
		Code.SKIPPED_POLICY:
			return &"skipped_policy"
		_:
			return &"failed"


static func is_rewarded_impression(code: int) -> bool:
	return code in [Code.EARNED, Code.CLOSED_WITHOUT_REWARD]
