import torch
import os
from lightglue import LightGlue, SuperPoint
from lightglue.utils import load_image, rbd
from google.adk.tools import FunctionTool
# from google_adk import Tool

class VisualZoneLocator():
    """
    Identifies the machine zone (e.g., front, rear, tire) from a query image 
    using feature matching against pre-defined anchor frames.
    """

    def __init__(self):
        
        super().__init__()
        current_dir = os.path.dirname(os.path.abspath(__file__))
        self.anchor_dir = os.path.abspath(os.path.join(current_dir, "..", "resources","images", "anchors"))

        self.device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
        
        self.extractor = SuperPoint(max_num_keypoints=1024).eval().to(self.device)
        self.matcher = LightGlue(features='superpoint').eval().to(self.device)
        
        # 2. Map and Pre-extract Anchor Features
        self.anchor_dict = {
            'frame_0018.jpg': "front_slight_sides",
            'frame_0033.jpg': "front_tire_left",
            'frame_0047.jpg': "left_center_rear_tire_left_service_panel",
            'frame_0068.jpg': "left_center_rear_tire_left_service_panel",
            'frame_0081.jpg': "rear_of_machine",
            'frame_0095.jpg': "right_center_rear_tire_right",
            'frame_0105.jpg': "right_center_rear_tire_right",
            'frame_0131.jpg': "front_tire_right",
        }
        
        self.anchor_feat = {}
        self._initialize_anchors(self.anchor_dir)

    def _initialize_anchors(self, anchor_dir):
        print(f"--- Pre-extracting features for {len(self.anchor_dict)} anchors ---")
        for filename, zone_name in self.anchor_dict.items():
            path = os.path.join(anchor_dir, filename)
            if os.path.exists(path):
                img, _, _ = load_image(path)
                feat = self.extractor.extract(img.to(self.device).unsqueeze(0))
                self.anchor_feat[zone_name] = feat
        print("--- Anchor initialization complete ---")

    def run(self, query_path: str) -> str:
        """
        Analyzes the image at query_path and returns the best matching zone name.
        
        Args:
            query_path: The file path to the query image to be analyzed.
        """
        image1, _, _ = load_image(query_path)
        feats1 = self.extractor.extract(image1.to(self.device).unsqueeze(0))
        
        best_score = 0
        best_zone = "Unknown"

        for zone, feats in self.anchor_feat.items():
            matches01 = self.matcher({'image0': feats, 'image1': feats1})
            num_matches = len(rbd(matches01)['matches'])
            if num_matches > best_score:
                best_score = num_matches
                best_zone = zone

        return f"The image most likely belongs to the zone: {best_zone} (Confidence Score: {best_score})"

# Instantiate the tool for use in your agent
locator_instance = VisualZoneLocator()
locate_zone = FunctionTool(func=locator_instance.run)