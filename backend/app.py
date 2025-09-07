from flask import Flask, request, jsonify
from flask_cors import CORS
from math import radians, sin, cos, sqrt, atan2
import mysql.connector
from mysql.connector import pooling, Error
import os
import logging

# ------------------ Setup ------------------
app = Flask(__name__)
CORS(app)  # Enable CORS for all routes

# Configure logging
logging.basicConfig(level=logging.INFO)

# ---------- MySQL Connection Pool ----------
dbconfig = {
    "host": os.environ.get("DB_HOST", "mysql-1a479660-bustracking4656s.d.aivencloud.com"),
    "user": os.environ.get("DB_USER", "avnadmin"),
    "password": os.environ.get("DB_PASSWORD", "AVNS_UyGORLroOQKmfeoeQ5H"),
    "database": os.environ.get("DB_NAME", "bus_location_tracking"),
}

# Pool size depends on free tier memory; adjust as needed
connection_pool = pooling.MySQLConnectionPool(
    pool_name="bus_pool",
    pool_size=5,
    **dbconfig
)

def get_db_connection():
    return connection_pool.get_connection()

# ---------- Helper: Haversine Distance ----------
def calculate_distance(lat1, lon1, lat2, lon2):
    R = 6371  # km
    dlat = radians(lat2 - lat1)
    dlon = radians(lon2 - lon1)
    a = sin(dlat / 2) ** 2 + cos(radians(lat1)) * cos(radians(lat2)) * sin(dlon / 2) ** 2
    c = 2 * atan2(sqrt(a), sqrt(1 - a))
    return R * c

# ---------- API Routes ----------

@app.route("/")
def home():
    return "🚍 Bus Tracking API is running"

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
        conn.commit()
        return jsonify({"message": "Bus registered successfully!", "bus_id": bus_id}), 201
    except Error as e:
        logging.error(f"Register bus error: {e}")
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
        conn.commit()
        return jsonify({"message": "Location updated successfully!"}), 201
    except Error as e:
        logging.error(f"Update location error: {e}")
        return jsonify({"error": str(e)}), 500
    finally:
        cursor.close()
        conn.close()

# 3️⃣ Get All Buses
@app.route("/get_nearby_buses", methods=["POST"])
def get_nearby_buses():
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        cursor.execute("""
            SELECT b.bus_id, b.bus_no, b.bus_name, b.popularity,
                   l.latitude, l.longitude, l.updated_at
            FROM latest_bus_location l
            JOIN buses b ON b.bus_id = l.bus_id
        """)
        rows = cursor.fetchall()
        result = [
            {
                "bus_id": r["bus_id"],
                "bus_no": r["bus_no"],
                "bus_name": r["bus_name"],
                "latitude": float(r["latitude"]),
                "longitude": float(r["longitude"]),
                "updated_at": r["updated_at"].isoformat() if r["updated_at"] else None,
                "popularity": r.get("popularity", 0),
            }
            for r in rows
        ]
        return jsonify(result)
    except Error as e:
        logging.error(f"Get buses error: {e}")
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
        conn.commit()
        return jsonify({"message": "Old locations cleaned up successfully."})
    except Error as e:
        logging.error(f"Cleanup error: {e}")
        return jsonify({"error": str(e)}), 500
    finally:
        cursor.close()
        conn.close()

# ---------- Run ----------
if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    app.run(debug=True, host="0.0.0.0", port=port, threaded=True)
