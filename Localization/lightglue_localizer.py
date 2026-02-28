import torch
from lightglue import LightGlue, SuperPoint, viz2d
from lightglue.utils import load_image, rbd

device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
# load feature extractor and feature matcher
extractor = SuperPoint(max_num_keypoints=1024).eval().to(device)
matcher = LightGlue(features='superpoint').eval().to(device)
# on startup
# anchor_dict = {
#     "front_slight_sides": 'anchors/frame_0018.jpg', #front
#     "front_tire_left": 'anchors/frame_0033.jpg', #frontleft
#     "left_center_rear_tire_left_service_panel": 'anchors/frame_0047.jpg', #left
#     "left_center_rear_tire_left_service_panel": 'anchors/frame_0068.jpg', #backleft
#     "rear_of_machine": 'anchors/frame_0081.jpg', #back
#     "right_center_rear_tire_right": 'anchors/frame_0095.jpg', #backright
#     "right_center_rear_tire_right": 'anchors/frame_0105.jpg', #right
#     "front_tire_right": 'anchors/frame_0131.jpg', #frontright
# }
anchor_dict = {
    'anchors/frame_0018.jpg': "front_slight_sides", #front
    'anchors/frame_0033.jpg': "front_tire_left", #frontleft
    'anchors/frame_0047.jpg': "left_center_rear_tire_left_service_panel", #left
    'anchors/frame_0068.jpg': "left_center_rear_tire_left_service_panel", #backleft
    'anchors/frame_0081.jpg': "rear_of_machine", #back
    'anchors/frame_0095.jpg': "right_center_rear_tire_right", #backright
    'anchors/frame_0105.jpg': "right_center_rear_tire_right", #right
    'anchors/frame_0131.jpg': "front_tire_right", #frontright
}
anchor_paths = ['anchors/frame_0018.jpg', 'anchors/frame_0033.jpg', 'anchors/frame_0047.jpg', 'anchors/frame_0068.jpg', 'anchors/frame_0081.jpg', 'anchors/frame_0095.jpg', 'anchors/frame_0105.jpg', 'anchors/frame_0131.jpg']
anchor_feat = {}
for a in anchor_paths:
    key = anchor_dict[a] 
    i, _, _ = load_image(a)
    feat = extractor.extract(i.to(device).unsqueeze(0))
    anchor_feat[key] = feat

def find_best_zone(query_path, anchor_feats):
    image1, _, _ = load_image(query_path)
    # extract feature points on image intelligently
    feats1 = extractor.extract(image1.to(device).unsqueeze(0))
    
    best_score = 0
    best_anchor = None
    best_zone = None
    for zone, feats in anchor_feats.items():
        # image0, _, _ = load_image(path)
        # feats0 = extractor.extract(image0.to(device).unsqueeze(0))
        
        # Match Query vs current Anchor
        matches01 = matcher({'image0': feats, 'image1': feats1})
        
        # Extract the number of valid matches
        matches = rbd(matches01)
        num_matches = len(matches['matches'])
        
        print(f"Checking {zone}: found {num_matches} matches")

        if num_matches > best_score:
            best_score = num_matches
            # best_anchor = path
            best_zone = zone

    return best_zone, best_score

# --- Example ----
winner, score = find_best_zone("test_images/testimage1.jpeg", anchor_feat)
print(f"Final Result: You are at {winner} (Score: {score})")