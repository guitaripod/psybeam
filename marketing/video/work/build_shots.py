import json

W, H, FPS = 1088, 1920, 24
NO_MUSIC = "ambient location sound only, no music, no voiceover narration"
GLOW = "a phone in hand, its screen showing only a soft, featureless blue-white glow, no visible text or icons"

STORIES = {
    "tokyo-ramen": {
        "traveler": "a Western woman in her early thirties, dark hair in a low ponytail, wearing a denim jacket over a plain top, a small brown backpack on one shoulder",
        "local": "a Japanese ramen chef in his forties, a dark blue headband, a white chef jacket with sleeves rolled up, broad calm hands",
        "scene": "a narrow wooden ramen counter in Tokyo at night, steam rising from bowls, warm hanging bulb lights, paper menus taped to the wall behind the counter, blurred neon street life through the open front",
        "establish_action": "the traveler sits down at the counter and settles her backpack beside her stool while the chef works behind the counter, wiping a bowl; steam drifts between them",
        "trav_action": f"she leans toward the counter, holding up {GLOW}, and says in a warm, clear voice, in English: \"Hi! One tonkotsu ramen, not too spicy, please.\"",
        "local_action": "the chef looks up, gives a small respectful nod and a brief bow of the head, and replies in a calm, clear voice, in Japanese: \"かしこまりました。少々お待ちください。\"",
        "payoff_action": "a steaming bowl of ramen is set down on the counter in front of her; she looks down at it and smiles, picking up her chopsticks",
    },
    "cdmx-tacos": {
        "traveler": "an American man in his mid-twenties, short dark hair, a light gray t-shirt, a canvas crossbody bag",
        "local": "a Mexican taquero in his thirties, a stained white apron over a checked shirt, a trimmed mustache, working a sizzling grill",
        "scene": "a corner taco stand in Mexico City at dusk, a metal grill sizzling with meat, string lights just switching on overhead, colorful papel picado banners, the city street blurred behind",
        "establish_action": "the traveler steps up to the stand as the taquero flips meat on the grill; smoke and the smell of the grill drift between them, string lights glowing warmer as dusk deepens",
        "trav_action": f"he steps closer to the counter, holding up {GLOW}, and says in a friendly, clear voice, in English: \"Three al pastor tacos, one without onion, please.\"",
        "local_action": "the taquero glances up with a quick smile, tongs still in hand, and replies in an easygoing, clear voice, in Spanish: \"¡Claro! ¿Con salsa verde o roja?\"",
        "payoff_action": "a paper plate of three tacos is slid across the counter to him; he picks one up and smiles, about to take a bite",
    },
    "paris-bakery": {
        "traveler": "a British woman in her forties, shoulder-length auburn hair, a camel-colored coat",
        "local": "a French baker in his fifties, flour dusted on his forearms, a white apron over a striped shirt",
        "scene": "a small Parisian boulangerie in the morning, wooden shelves stacked with baguettes and croissants, warm morning light through the front window, a glass display counter between them",
        "establish_action": "the traveler steps up to the glass counter as the baker arranges fresh croissants behind it; morning light catches drifting flour dust in the air",
        "trav_action": f"she leans toward the counter, holding up {GLOW}, and says in a polite, clear voice, in English: \"Two croissants and a baguette, please. Is this one still warm?\"",
        "local_action": "the baker smiles and picks up a croissant with a small paper square, replying in a warm, clear voice, in French: \"Oui, elle sort du four à l'instant !\"",
        "payoff_action": "he hands her a paper bag of pastries across the counter; she takes it and smiles, holding it close",
    },
    "rome-trattoria": {
        "traveler": "an American couple in their mid-thirties, a woman with dark wavy hair in a linen dress and a man with short brown hair in a light blazer, seated close together",
        "local": "an Italian waiter in his fifties, a black waistcoat over a white shirt, a neatly trimmed beard, notepad in hand",
        "scene": "a cozy trattoria terrace in Rome in the early evening, a red-checkered tablecloth, string lights overhead, terracotta buildings glowing in the background light",
        "establish_action": "the couple sits close together at the terrace table looking over menus as the waiter approaches with his notepad; string lights flicker on above them",
        "trav_action": f"the woman looks up at the waiter, the man's hand resting on the table beside {GLOW}, and says in a warm, clear voice, in English: \"We'd love the cacio e pepe and a carafe of house red.\"",
        "local_action": "the waiter nods, jotting on his notepad, and replies in a friendly, clear voice, in Italian: \"Ottima scelta, arriva subito.\"",
        "payoff_action": "the waiter sets down a carafe of red wine on the table; the couple lean in together and smile at each other",
    },
    "bangkok-market": {
        "traveler": "an Australian man in his early thirties, sandy hair, a faded green t-shirt, a woven wristband",
        "local": "a Thai street-food vendor woman in her forties, a straw hat pushed back, an apron over a floral blouse, stirring a wok",
        "scene": "a busy night-market food stall in Bangkok, a wok with visible steam and flame, blurred glowing neon signage in the background, strings of paper lanterns overhead",
        "establish_action": "the traveler steps up to the stall as the vendor tosses noodles in a flaming wok; steam and lantern light swirl around the stall",
        "trav_action": f"he leans toward the stall, holding up {GLOW}, and says in a friendly, clear voice, in English: \"One pad thai, medium spicy, with extra lime please.\"",
        "local_action": "the vendor glances up with a quick smile, wok still in motion, and replies in a bright, clear voice, in Thai: \"ได้ค่ะ รอสักครู่นะคะ\"",
        "payoff_action": "she slides a plate of pad thai with a lime wedge across the counter to him; he picks it up and smiles, steam rising from the plate",
    },
    "seoul-pharmacy": {
        "traveler": "an American woman in her late twenties, a dark bob haircut, a beige trench coat",
        "local": "a Korean pharmacist in her thirties, round glasses, a white pharmacist coat, a name badge on the chest",
        "scene": "a small tidy pharmacy in Seoul, shelves of medicine boxes behind the counter, soft fluorescent light, a jar of throat candies on the counter",
        "establish_action": "the traveler steps up to the counter, one hand at her throat, as the pharmacist looks up from a shelf of boxes behind the counter",
        "trav_action": f"she gestures gently at her throat, holding up {GLOW} in her other hand, and asks in a soft, clear voice, in English: \"Do you have something for a sore throat?\"",
        "local_action": "the pharmacist nods and reaches for two items on the shelf behind her, replying in a warm, clear voice, in Korean: \"네, 이 목캔디랑 이 약을 추천해요.\"",
        "payoff_action": "the pharmacist sets a small box of medicine and a tin of throat candies on the counter; the traveler smiles and nods, reaching for them",
    },
    "kyoto-shop": {
        "traveler": "a Western tourist woman in her thirties, blonde hair pulled back, fair skin, sunglasses pushed up on her head, wearing a light linen sundress, a small crossbody bag, clearly a foreign visitor to Japan, browsing shelves",
        "local": "a Japanese shopkeeper in his fifties, silver-gray hair, an indigo happi coat over a collared shirt, reading glasses on a cord around his neck",
        "scene": "a small traditional souvenir shop in Kyoto, wooden shelves of folded textiles and pottery, paper lanterns, soft daylight filtering through a shoji screen",
        "establish_action": "the tourist picks up a folded textile from a shelf and turns toward the shopkeeper, who stands behind a low wooden counter holding a phone",
        "trav_action": "she holds up the folded textile and asks the shopkeeper in a polite, clear voice, in English: \"Do you have this in a smaller size?\"",
        "local_action": f"the shopkeeper looks down at {GLOW} in his hand, then nods and replies in a warm, clear voice, in Japanese: \"はい、こちらに小さいサイズがございます。\"",
        "payoff_action": "the shopkeeper reaches under the counter and sets a smaller folded textile down; the tourist smiles and nods, picking it up to compare",
    },
}

def build_prompt(shot_kind, s):
    scene = s["scene"]
    if shot_kind == "establish":
        return (
            f"Vertical wide establishing shot. Scene: {scene}. "
            f"Action: {s['establish_action']}. "
            f"Characters: on one side, {s['traveler']}; on the other side, {s['local']}. "
            f"Camera: static wide shot, both figures clearly in frame, very slight handheld breathing motion, no cuts. "
            f"Audio: {NO_MUSIC}."
        )
    if shot_kind == "traveler":
        return (
            f"Vertical medium close-up shot. Scene: {scene}, the same counter and lighting as before. "
            f"Action: {s['trav_action']}. "
            f"Character: {s['traveler']}, same appearance and outfit as established. "
            f"Camera: slow smooth push-in toward her as she speaks, settling on a medium close-up. "
            f"Audio: {NO_MUSIC}, her line is the only speech, clearly audible and lip-synced."
        )
    if shot_kind == "local":
        return (
            f"Vertical medium close-up shot. Scene: {scene}, the same counter and lighting as before. "
            f"Action: {s['local_action']}. "
            f"Character: {s['local']}, same appearance and outfit as established. "
            f"Camera: slow smooth push-in toward them as they speak, settling on a medium close-up. "
            f"Audio: {NO_MUSIC}, their line is the only speech, clearly audible and lip-synced."
        )
    if shot_kind == "payoff":
        return (
            f"Vertical medium close-up shot, continuous with the previous close-up on the traveler. "
            f"Scene: {scene}. "
            f"Action: {s['payoff_action']}. "
            f"Character: {s['traveler']}, same appearance and outfit as established, no new dialogue, just a warm satisfied reaction. "
            f"Camera: static medium close-up, very slight handheld breathing motion. "
            f"Audio: {NO_MUSIC}, no dialogue in this shot."
        )
    raise ValueError(shot_kind)

def build_story_shots(story_id, s, seed_base):
    return [
        {
            "story": story_id, "role": "establish", "name": f"{story_id}_1_establish",
            "mode": "t2v", "prompt": build_prompt("establish", s),
            "seconds": 3, "width": W, "height": H, "fps": FPS, "seed": seed_base + 1,
            "has_dialogue": False, "speaker": None, "depends_on": None,
        },
        {
            "story": story_id, "role": "traveler", "name": f"{story_id}_2_traveler",
            "mode": "i2v", "prompt": build_prompt("traveler", s),
            "seconds": 4, "width": W, "height": H, "fps": FPS, "seed": seed_base + 2,
            "has_dialogue": True, "speaker": "traveler", "depends_on": f"{story_id}_1_establish",
        },
        {
            "story": story_id, "role": "local", "name": f"{story_id}_3_local",
            "mode": "i2v", "prompt": build_prompt("local", s),
            "seconds": 4, "width": W, "height": H, "fps": FPS, "seed": seed_base + 3,
            "has_dialogue": True, "speaker": "local", "depends_on": f"{story_id}_1_establish",
        },
        {
            "story": story_id, "role": "payoff", "name": f"{story_id}_4_payoff",
            "mode": "i2v", "prompt": build_prompt("payoff", s),
            "seconds": 3, "width": W, "height": H, "fps": FPS, "seed": seed_base + 4,
            "has_dialogue": False, "speaker": None, "depends_on": f"{story_id}_2_traveler",
        },
    ]

all_shots = []
for i, (story_id, s) in enumerate(STORIES.items()):
    all_shots.extend(build_story_shots(story_id, s, seed_base=10000 + i * 100))

with open("/Users/marcus/Dev/ios/psybeam/marketing/video/work/stories_shots.json", "w") as f:
    json.dump(all_shots, f, indent=1, ensure_ascii=False)

print(f"{len(all_shots)} shots across {len(STORIES)} stories")
