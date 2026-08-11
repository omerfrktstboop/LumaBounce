class_name PurchaseResult
extends RefCounted

## Google Play ayrintilarini UI ve analytics yuzeyinden uzak tutan sonuc kodlari.

enum Code {
	PURCHASED,
	PENDING,
	CANCELLED,
	FAILED,
	UNAVAILABLE,
	ALREADY_OWNED,
	RESTORED,
}


static func key(code: int) -> String:
	match code:
		Code.PURCHASED:
			return "purchased"
		Code.PENDING:
			return "pending"
		Code.CANCELLED:
			return "cancelled"
		Code.FAILED:
			return "failed"
		Code.UNAVAILABLE:
			return "unavailable"
		Code.ALREADY_OWNED:
			return "already_owned"
		Code.RESTORED:
			return "restored"
		_:
			return "unknown"
