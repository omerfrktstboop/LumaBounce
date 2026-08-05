import os
import math
import random

def create_level(level_id, display_name):
    # Base setup
    target_pos = "Vector2(360, 150)"
    launcher_pos = "Vector2(360, 1120)"
    target_scale = 0.8
    ball_scale = 0.65
    
    target_pos_val = (360, 150)

    sub_resources = []
    blocks_str = ""
    obstacles_str = ""
    panels_str = ""

    def dist(x1, y1, x2, y2):
        return math.sqrt((x1-x2)**2 + (y1-y2)**2)
    
    def add_brick(r_id, x, y, hp=1):
        nonlocal blocks_str
        sub_resources.append(f'''[sub_resource type="Resource" id="{r_id}"]
script = ExtResource("1")
position = Vector2({x}, {y})
size = Vector2(40, 20)
hit_points = {hp}''')
        blocks_str += f'SubResource("{r_id}"), '

    def add_obstacle(r_id, kind, x, y, size_x, size_y=40, extras=""):
        nonlocal obstacles_str
        sub_resources.append(f'''[sub_resource type="Resource" id="{r_id}"]
script = ExtResource("2")
kind = {kind}
position = Vector2({x}, {y})
rotation_degrees = 0.0
size = Vector2({size_x}, {size_y})
{extras}''')
        obstacles_str += f'SubResource("{r_id}"), '

    def add_boost(r_id, x, y):
        add_obstacle(r_id, 4, x, y, 40, 40, "inner_radius = 42.0\nspoke_count = 6\nangular_speed_degrees = 55.0\nmotion_direction_degrees = 0.0\ntravel_distance = 110.0\nmotion_period = 2.8\nphase_degrees = 0.0")

    def add_ring(r_id, x, y, inner_r):
        outer = inner_r + 20
        add_obstacle(r_id, 0, x, y, outer * 2.0, 28, f"inner_radius = {inner_r}\nspoke_count = 6\nangular_speed_degrees = 55.0\nmotion_direction_degrees = 0.0\ntravel_distance = 110.0\nmotion_period = 2.8\nphase_degrees = 0.0")
        
    def add_bomb(r_id, x, y, radius=50):
        add_obstacle(r_id, 1, x, y, radius*2, 28, "inner_radius = 42.0\nspoke_count = 6\nangular_speed_degrees = 55.0\nmotion_direction_degrees = 0.0\ntravel_distance = 110.0\nmotion_period = 2.8\nphase_degrees = 0.0")
        
    def add_wheel(r_id, x, y, speed, spoke=5):
        add_obstacle(r_id, 2, x, y, 100, 20, f"inner_radius = 42.0\nspoke_count = {spoke}\nangular_speed_degrees = {speed}\nmotion_direction_degrees = 0.0\ntravel_distance = 110.0\nmotion_period = 2.8\nphase_degrees = 0.0")

    def add_mover(r_id, x, y, dist, period, dir_deg):
        add_obstacle(r_id, 3, x, y, 100, 30, f"inner_radius = 42.0\nspoke_count = 6\nangular_speed_degrees = 55.0\nmotion_direction_degrees = {dir_deg}\ntravel_distance = {dist}\nmotion_period = {period}\nphase_degrees = 0.0")

    def add_panel(r_id, x, y, rot, length):
        nonlocal panels_str
        sub_resources.append(f'''[sub_resource type="Resource" id="{r_id}"]
script = ExtResource("3")
position = Vector2({x}, {y})
rotation_degrees = {rot}
length = {length}''')
        panels_str += f'SubResource("{r_id}"), '

    # Difficulty increases from 0.0 to 1.0 between 1 and 75
    difficulty = level_id / 75.0
    pattern_type = level_id % 6
    
    # Tutorials & Boss
    if level_id == 75:
        # BOSS LEVEL
        target_pos_val = (360, 150)
        target_pos = f"Vector2({target_pos_val[0]}, {target_pos_val[1]})"
        add_ring("BossRing", 360, 150, 60.0)
        add_wheel("BossWheel_L", 150, 400, 100, 6)
        add_wheel("BossWheel_R", 570, 400, -100, 6)
        add_mover("BossMov_1", 360, 600, 150, 2.5, 0.0)
        add_bomb("BossBomb_1", 200, 800, 40)
        add_bomb("BossBomb_2", 520, 800, 40)
        add_boost("BossBoost_1", 360, 1000)
        for i in range(16):
            add_brick(f"B_{i}", 360 + math.cos(i)*120, 400 + math.sin(i)*120, 3)
    elif level_id == 25:
        # MID-BOSS LEVEL 25
        target_pos_val = (360, 200)
        target_pos = f"Vector2({target_pos_val[0]}, {target_pos_val[1]})"
        for i in range(12):
            add_brick(f"B_{i}", 360 + math.cos(i)*100, 200 + math.sin(i)*100, 2)
        add_panel("P_1", 360, 500, 0, 300)
    elif level_id == 50:
        # MID-BOSS LEVEL 50
        target_pos_val = (360, 200)
        target_pos = f"Vector2({target_pos_val[0]}, {target_pos_val[1]})"
        for i in range(20):
            add_brick(f"B_{i}", 360 + math.cos(i)*150, 200 + math.sin(i)*150, 3)
        add_panel("P_1", 200, 500, 45, 200)
        add_panel("P_2", 520, 500, -45, 200)
    elif pattern_type == 0:
        # Pockets & Movers
        target_pos_val = (360, 150)
        target_pos = f"Vector2({target_pos_val[0]}, {target_pos_val[1]})"
        for i in range(12 + int(difficulty*10)):
            x = random.randint(150, 570)
            y = random.randint(300, 600)
            if dist(x, y, target_pos_val[0], target_pos_val[1]) > 100:
                add_brick(f"B_{i}", x, y, 1)
        
        add_boost("Boost_1", 360, 700)
        if difficulty > 0.3:
            add_mover("Mov_1", 360, 400, 150, max(2.0, 5.0 - difficulty*3), 0.0)
        if difficulty > 0.6:
            add_bomb("Bomb_1", 200, 300, 35)
            add_bomb("Bomb_2", 520, 300, 35)
            
    elif pattern_type == 1:
        # Wheels & Panels
        target_pos_val = (360, 200)
        target_pos = f"Vector2({target_pos_val[0]}, {target_pos_val[1]})"
        add_panel("P_1", 150, 700, 35, 200)
        add_panel("P_2", 570, 700, -35, 200)
        
        speed = 40 + difficulty * 60
        add_wheel("W_1", 200, 500, speed)
        add_wheel("W_2", 520, 500, -speed)
        
        if difficulty > 0.4:
            add_wheel("W_3", 360, 350, speed * 1.2, 3)
            
        add_boost("Boost_1", 360, 800)
        for i in range(8 + int(difficulty*5)):
            x = random.randint(200, 520)
            y = random.randint(200, 300)
            if dist(x, y, target_pos_val[0], target_pos_val[1]) > 100:
                add_brick(f"B_{i}", x, y, 2)
            
    elif pattern_type == 2:
        # Ring protected target
        target_pos_val = (360, 300)
        target_pos = f"Vector2({target_pos_val[0]}, {target_pos_val[1]})"
        add_ring("Ring_1", 360, 300, max(45.0, 90.0 - difficulty*40))
        
        add_panel("P_1", 360, 800, 0, 150)
        add_boost("Boost_1", 150, 600)
        add_boost("Boost_2", 570, 600)
        
        if difficulty > 0.5:
            add_mover("Mov_1", 360, 500, 120, 3.0, 0.0)
            add_bomb("Bomb_1", 360, 400, 40)
            
    elif pattern_type == 3:
        # Zig-Zag with Bombs
        target_pos_val = (150, 150)
        target_pos = f"Vector2({target_pos_val[0]}, {target_pos_val[1]})"
        add_panel("P_1", 400, 600, 30, 250)
        add_panel("P_2", 300, 400, -30, 250)
        
        add_boost("Boost_1", 360, 750)
        
        if difficulty > 0.2:
            add_bomb("Bomb_1", 300, 600, 30)
            add_bomb("Bomb_2", 400, 400, 30)
            
        for i in range(5 + int(difficulty*10)):
            x = random.randint(150, 570)
            y = random.randint(150, 300)
            if dist(x, y, target_pos_val[0], target_pos_val[1]) > 100:
                add_brick(f"B_{i}", x, y, 2)
            
    elif pattern_type == 4:
        # Cross of Movers
        target_pos_val = (360, 400)
        target_pos = f"Vector2({target_pos_val[0]}, {target_pos_val[1]})"
        add_mover("Mov_H", 360, 250, 100, 3.0, 0.0)
        add_mover("Mov_V", 250, 400, 100, 3.5, 90.0)
        if difficulty > 0.5:
            add_mover("Mov_V2", 470, 400, 100, 3.5, 90.0)
            
        add_boost("Boost_1", 360, 700)
        add_boost("Boost_2", 360, 150)
        
        for i in range(10):
            x = 360 + math.cos(i)*100
            y = 400 + math.sin(i)*100
            if dist(x, y, target_pos_val[0], target_pos_val[1]) > 100:
                add_brick(f"B_{i}", x, y, 1)

    elif pattern_type == 5:
        # Bomb Minefield
        target_pos_val = (360, 120)
        target_pos = f"Vector2({target_pos_val[0]}, {target_pos_val[1]})"
        num_bombs = 3 + int(difficulty*6)
        for i in range(num_bombs):
            x = random.randint(150, 570)
            # Spawn lower to give room
            y = random.randint(350, 700)
            if dist(x, y, target_pos_val[0], target_pos_val[1]) > 100:
                add_bomb(f"Bomb_{i}", x, y, 25)
            
        add_boost("Boost_1", 360, 400)
        add_boost("Boost_2", 200, 250)
        add_boost("Boost_3", 520, 250)
        
    blocks_arr = f"Array[BreakableBlockData]([{blocks_str.strip(', ')}])"
    obstacles_arr = f"Array[ObstacleData]([{obstacles_str.strip(', ')}])"
    panels_arr = f"Array[PanelData]([{panels_str.strip(', ')}])"
    
    content = f'''[gd_resource type="Resource" script_class="LevelData" format=3]

[ext_resource type="Script" path="res://scripts/levels/breakable_block_data.gd" id="1"]
[ext_resource type="Script" path="res://scripts/levels/obstacle_data.gd" id="2"]
[ext_resource type="Script" path="res://scripts/levels/panel_data.gd" id="3"]
[ext_resource type="Script" path="res://scripts/levels/level_data.gd" id="4"]

{chr(10).join(sub_resources)}

[resource]
script = ExtResource("4")
level_id = {level_id}
display_name = "{display_name}"
launcher_position = {launcher_pos}
target_position = {target_pos}
target_scale = {target_scale}
ball_scale = {ball_scale}
panels = {panels_arr}
breakable_blocks = {blocks_arr}
obstacles = {obstacles_arr}
left_wall_segments = Array[Vector2]([])
right_wall_segments = Array[Vector2]([])
max_lives = 5
tutorial_text = ""
two_star_max_seconds = 60.0
two_star_max_shots = 6
three_star_max_seconds = 35.0
three_star_max_shots = 3
'''
    return content

for i in range(51, 76):
    diff = i - 50
    content = create_level(i, f"Turuncu Faz {diff}")
    with open(f"D:/Windows/Desktop/LumaBounce/levels/level_{i}.tres", "w", encoding="utf-8") as f:
        f.write(content)

for i in range(30, 41):
    content = create_level(i, f"Sıcak Faz {i}")
    with open(f"D:/Windows/Desktop/LumaBounce/levels/level_{i}.tres", "w", encoding="utf-8") as f:
        f.write(content)

# Generate Boss levels 25 and 50
content25 = create_level(25, "Boss Faz 1")
with open("D:/Windows/Desktop/LumaBounce/levels/level_25.tres", "w", encoding="utf-8") as f:
    f.write(content25)

content50 = create_level(50, "Boss Faz 2")
with open("D:/Windows/Desktop/LumaBounce/levels/level_50.tres", "w", encoding="utf-8") as f:
    f.write(content50)

print("Levels 30-40, 51-75 and bosses 25, 50 generated.")
