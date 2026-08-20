class_name Rulebooks
extends RefCounted

## Which rulebooks a campaign has made active.
##
## The books themselves are global to the installation and live in Redline's
## private application data — never inside a `.red` file. A campaign stores only
## the IDs of the books its table plays with, in the order the GM arranged them,
## so a save can be shared without carrying a line of anyone's sourcebook.
##
## An ID whose book is not installed here is kept rather than dropped. The GM who
## owns that book still resolves it on their machine; on this one the Assistant
## tab simply reports the source as unavailable.

const CAMPAIGN_KEY := "active_rulebook_ids"

## The helper identifies a book by the first sixteen hex characters of its
## SHA-256. Requiring that shape here means a hand-edited or hostile campaign
## file cannot put anything path-like into the request the Assistant tab builds.
const MIN_ID_LENGTH := 8
const MAX_ID_LENGTH := 64
const MAX_ACTIVE_BOOKS := 64


static func is_valid_id(id: String) -> bool:
	if id.length() < MIN_ID_LENGTH or id.length() > MAX_ID_LENGTH:
		return false
	for index in id.length():
		var character := id[index]
		var hexadecimal := (
			(character >= "0" and character <= "9") or (character >= "a" and character <= "f")
		)
		if not hexadecimal:
			return false
	return true


## Clean a stored list: trimmed, lowercased, de-duplicated, order preserved.
static func sanitize(ids: Array) -> Array:
	var cleaned: Array = []
	for value in ids:
		if not value is String:
			continue
		var id := String(value).strip_edges().to_lower()
		if is_valid_id(id) and not cleaned.has(id):
			cleaned.append(id)
		if cleaned.size() >= MAX_ACTIVE_BOOKS:
			break
	return cleaned


## Give an older campaign the field, without disturbing one that has it.
static func ensure_campaign(campaign: Dictionary) -> void:
	var stored: Array = []
	if campaign.has(CAMPAIGN_KEY) and campaign[CAMPAIGN_KEY] is Array:
		stored = campaign[CAMPAIGN_KEY]
	campaign[CAMPAIGN_KEY] = sanitize(stored)


static func active_ids(campaign: Dictionary) -> Array:
	ensure_campaign(campaign)
	return campaign[CAMPAIGN_KEY]


static func is_active(campaign: Dictionary, id: String) -> bool:
	return active_ids(campaign).has(id.strip_edges().to_lower())


## Turn one book on or off for this campaign. Returns whether anything changed.
static func set_active(campaign: Dictionary, id: String, active: bool) -> bool:
	var cleaned := id.strip_edges().to_lower()
	if not is_valid_id(cleaned):
		return false
	var ids := active_ids(campaign)
	var index := ids.find(cleaned)
	if active and index == -1:
		if ids.size() >= MAX_ACTIVE_BOOKS:
			return false
		ids.append(cleaned)
		return true
	if not active and index != -1:
		ids.remove_at(index)
		return true
	return false


## Move a book up or down the search order the GM sees.
static func move(campaign: Dictionary, id: String, delta: int) -> bool:
	var ids := active_ids(campaign)
	var index := ids.find(id.strip_edges().to_lower())
	if index == -1 or delta == 0:
		return false
	var target := clampi(index + delta, 0, ids.size() - 1)
	if target == index:
		return false
	var moved: String = ids[index]
	ids.remove_at(index)
	ids.insert(target, moved)
	return true


## Match the campaign's IDs against the books this installation actually holds.
##
## [param installed] is the helper's library listing. The result keeps the
## campaign's order, and names every ID whose book is missing here so the tab can
## say so instead of quietly searching less than the GM believes it is.
static func resolve(campaign: Dictionary, installed: Array) -> Dictionary:
	var by_id := {}
	for value in installed:
		var book: Dictionary = value
		by_id[String(book.get("book_id", ""))] = book
	var active: Array = []
	var unavailable: Array = []
	for value in active_ids(campaign):
		var id := String(value)
		if by_id.has(id):
			active.append(by_id[id])
		else:
			unavailable.append(id)
	return {"active": active, "unavailable": unavailable}


## The books that can actually answer a question right now.
static func searchable_ids(campaign: Dictionary, installed: Array) -> Array:
	var ready: Array = []
	for value in (resolve(campaign, installed)["active"] as Array):
		var book: Dictionary = value
		if String(book.get("status", "")) == "indexed" and int(book.get("chunk_count", 0)) > 0:
			ready.append(String(book["book_id"]))
	return ready
