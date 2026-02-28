import cv2
import json
def find_best_anchor(query_img, anchor_dict):
    """
    anchor_dict: {'frame_0018.jpg': image_data, 'frame_0047.jpg': image_data, ...}
    Returns: best_filename, best_match_count
    """
    # 1. Ensure query is grayscale
    if len(query_img.shape) == 3:
        query_img = cv2.cvtColor(query_img, cv2.COLOR_BGR2GRAY)

    sift = cv2.SIFT_create()
    kp_q, des_q = sift.detectAndCompute(query_img, None)
    
    best_match_count = 0
    best_filename = None
    best_pos = None
    for pos, anchor_data in anchor_dict.items():
        # Ensure anchor is grayscale
        if len(anchor_data.shape) == 3:
            anchor_data = cv2.cvtColor(anchor_data, cv2.COLOR_BGR2GRAY)
            
        kp_a, des_a = sift.detectAndCompute(anchor_data, None)
        
        # Match features
        bf = cv2.BFMatcher()
        matches = bf.knnMatch(des_q, des_a, k=2)
        
        # Ratio test
        good = [m for m, n in matches if m.distance < 0.75 * n.distance]
        
        if len(good) > best_match_count:
            best_match_count = len(good)
            # best_filename = filename
            best_pos = pos
        
    return best_pos, best_match_count

# --- Usage Example ---
# front, front-left, left, back-left, back, back-right, right
anchor_dict = {
    "front_slight_sides": cv2.imread("images/frame_0018.jpg"), #front
    "front_tire_left": cv2.imread("images/frame_0033.jpg"), #frontleft
    "left_center_rear_tire_left_service_panel": cv2.imread("images/frame_0047.jpg"), #left
    "left_center_rear_tire_left_service_panel": cv2.imread("images/frame_0068.jpg"), #backleft
    "rear_of_machine": cv2.imread("images/frame_0081.jpg"), #back
    "right_center_rear_tire_right": cv2.imread("images/frame_0095.jpg"), #backright
    "right_center_rear_tire_right": cv2.imread("images/frame_0105.jpg"), #right
    "front_tire_right": cv2.imread("images/frame_0131.jpg"), #frontright
}
anchor_paths = ['anchors/frame_0018.jpg', 'anchors/frame_0033.jpg', 'anchors/frame_0047.jpg', 'anchors/frame_0068.jpg', 'anchors/frame_0081.jpg', 'anchors/frame_0095.jpg', 'anchors/frame_0105.jpg', 'anchors/frame_0131.jpg']
# Create the dictionary
anchors = {path: cv2.imread(path) for path in anchor_paths}

query = cv2.imread('test_images/testimage1.jpeg')
pos, score = find_best_anchor(query, anchor_dict)
with open('components.json', 'r') as f:
    anchor_data = json.load(f)
zone = next((z for z in anchor_data["zones"] if z["zone_id"] == pos), None)
# match_info = anchor_data[pos]

print(f"Match found! Best anchor: {pos} with {score} matching points.")
print(f"Match info: {zone}")