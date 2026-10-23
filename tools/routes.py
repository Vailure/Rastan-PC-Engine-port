"""Input routes through round 1 (tgrun key lists), shared by the tests and tools/audit.py."""
I = '40'

def shift(route, d):
    """The same route d frames later."""
    return [v + d if isinstance(v, int) else v for v in route]


# Route A, measured against this build (the arcade cannot be driven through here):
# 830 waits for the middle corridor's floor spears to sink; the four jumps from 2990
# cross the lava hall on its three vines.
ROUTE_A = [200, 449, '04', 450, 453, '08', 470, 473, '41', 474, 700, '01', 710, 713, '48', 714, 760, '08',
           830, 1050, '08', 1055, 1058, '04', 1070, 1073, '41', 1074, 1310, '01', 1320, 1323, '44',
           1324, 1580, '04', 1581, 1584, '08', 1600, 1603, '41', 1604, 1840, '01', 1850, 1853, '48',
           1854, 2080, '08', 2081, 2100, '04', 2105, 2108, '41', 2109, 2460, '01', 2470, 2473, '44',
           2474, 2639, '04', 2645, 2648, '41', 2649, 2840, '01', 2850, 2853, '44', 2854, 2989, '04',
           2990, 2993, '45', 2994, 3123, '04', 3124, 3127, '44', 3128, 3229, '04', 3230, 3233, '44',
           3234, 3329, '04', 3330, 3333, '44', 3334, 3600, '04']
# (Measured before warps cut to black for two more frames: it starts that much later.)
ROUTE_A = shift(ROUTE_A, 2)
# The same up to the top of shaft 1's lower rope, where he hangs still.
ROUTE_SHAFT = ROUTE_A[:ROUTE_A.index(2472)]

ROUTE_B = [200, 830, '05'] + sum([[f, f + 3, I] for f in range(220, 830, 60)], []) + [
    831, 1100, '04', 864, 867, I, 914, 917, I, 964, 967, I, 1101, 1103, '08', 1110, 1113, '41', 1114, 1470, '01',
    1480, 1483, '48', 1484, 1572, '08', 1590, 1593, '41', 1594, 1830, '01', 1840, 1843, '48', 1844, 1990, '08',
    1991, 1995, '04', 2010, 2013, '41', 2014, 2280, '01', 2290, 2293, '44', 2294, 2491, '04', 2510, 2513, '41',
    2514, 2760, '01', 2770, 2773, '48', 2774, 3100, '08'] + sum([[f, f + 1, '80'] for f in range(3150, 3800, 25)], [])

ROUTE_V = [200, 350, '04', 360, 363, '41', 364, 600, '01', 610, 613, '44', 614, 1300, '04', 730, 733, '44',
           832, 835, '45', 965, 968, '44']
