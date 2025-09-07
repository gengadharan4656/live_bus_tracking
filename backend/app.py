from flask import Flask, request, jsonify
from math import radians, sin, cos, sqrt, atan2
import mysql.connector
from mysql.connector import Error

app = Flask(__name__)

# ---------- MySQL Connection ----------
def get_db_connection():
    return mysql.connector.connect(
        host="localhost",
        user="root",
        password="Dharan$$4656",
        database="bus_tracking",
        autocommit=True
    )

# ---------- Helper: Haversine Distance ----------
def calculate_distance(lat1, lon1, lat2, lon2):
    R = 6371  # Earth radius in km
    dlat = radians(lat2 - lat1)
    dlon = radians(lon2 - lon1)
    a = sin(dlat / 2) ** 2 + cos(radians(lat1)) * cos(radians(lat2)) * sin(dlon / 2) ** 2
    c = 2 * atan2(sqrt(a), sqrt(1 - a))
    return R * c

# ---------- API Routes ----------

# 1️⃣ Register a bus
@app.route("/register_bus", methods=["POST"])
def register_bus():
    data = request.json
    if not data or "bus_no" not in data or "bus_name" not in data:
        return jsonify({"error": "Missing bus_no or bus_name"}), 400
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute(
            "INSERT INTO buses (bus_no, bus_name) VALUES (%s, %s)",
            (data["bus_no"], data["bus_name"])
        )
        bus_id = cursor.lastrowid
        return jsonify({"message": "Bus registered successfully!", "bus_id": bus_id}), 201
    except Error as e:
        return jsonify({"error": str(e)}), 500
    finally:
        cursor.close()
        conn.close()

# 2️⃣ Update Bus Location
@app.route("/update_location", methods=["POST"])
def update_location():
    data = request.json
    if not data or "bus_id" not in data or "latitude" not in data or "longitude" not in data:
        return jsonify({"error": "Missing bus_id, latitude, or longitude"}), 400

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        # UPSERT latest location
        cursor.execute("""
            INSERT INTO latest_bus_location (bus_id, latitude, longitude, location)
            VALUES (%s, %s, %s, ST_SRID(POINT(%s, %s), 4326))
            ON DUPLICATE KEY UPDATE latitude=VALUES(latitude),
                                    longitude=VALUES(longitude),
                                    location=VALUES(location),
                                    updated_at=NOW()
        """, (data["bus_id"], data["latitude"], data["longitude"],
              data["longitude"], data["latitude"]))

        # Insert into history
        cursor.execute("""
            INSERT INTO bus_locations (bus_id, latitude, longitude, location)
            VALUES (%s, %s, %s, ST_SRID(POINT(%s, %s), 4326))
        """, (data["bus_id"], data["latitude"], data["longitude"],
              data["longitude"], data["latitude"]))

        return jsonify({"message": "Location updated successfully!"}), 201
    except Error as e:
        return jsonify({"error": str(e)}), 500
    finally:
        cursor.close()
        conn.close()

# 3️⃣ Get Nearby Buses (sorted by nearest first)
@app.route("/get_nearby_buses", methods=["POST"])
def get_nearby_buses():
    data = request.json
    try:
        user_lat = float(data.get("latitude"))
        user_lon = float(data.get("longitude"))
    except (TypeError, ValueError):
        return jsonify({"error": "Invalid latitude/longitude"}), 400

    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)

        user_point = f"ST_SRID(POINT({user_lon}, {user_lat}), 4326)"

        # Fetch all buses without distance restriction
        query = f"""
        SELECT b.bus_id, b.bus_no, b.bus_name, b.popularity,
               l.latitude, l.longitude, l.updated_at,
               ST_Distance_Sphere(l.location, {user_point}) AS distance_meters
        FROM latest_bus_location l
        JOIN buses b ON b.bus_id = l.bus_id
        ORDER BY distance_meters ASC
        """
        cursor.execute(query)
        rows = cursor.fetchall()

        result = [
            {
                "bus_id": r["bus_id"],
                "bus_no": r["bus_no"],
                "bus_name": r["bus_name"],
                "latitude": float(r["latitude"]),
                "longitude": float(r["longitude"]),
                "distance_m": round(float(r["distance_meters"]), 1),
                "updated_at": r["updated_at"].isoformat() if r["updated_at"] else None,
                "popularity": r.get("popularity", 0),
            }
            for r in rows
        ]

        return jsonify(result)
    except Error as e:
        return jsonify({"error": str(e)}), 500
    finally:
        cursor.close()
        conn.close()


# 4️⃣ Cleanup old locations
@app.route("/cleanup_old_locations", methods=["POST"])
def cleanup_old_locations():
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("DELETE FROM bus_locations WHERE recorded_at < NOW() - INTERVAL 1 DAY")
        return jsonify({"message": "Old locations cleaned up successfully."})
    except Error as e:
        return jsonify({"error": str(e)}), 500
    finally:
        cursor.close()
        conn.close()

# 5️⃣ Home
@app.route("/")
def home():
    return "🚍 Bus Tracking API (MySQL + Flask) is running"

# ---------- Run ----------
if __name__ == "__main__":
    app.run(debug=True, host="0.0.0.0", port=5000)
