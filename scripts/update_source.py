"""Ajoute (ou remplace) une version de BlueScreen dans la source AltStore.
Usage : python3 scripts/update_source.py VERSION BUILD TAILLE URL_IPA"""
import json, sys, datetime, os
version, build, size, url = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
p = os.path.join(os.path.dirname(__file__), "..", "altstore", "source.json")
src = json.load(open(p, encoding="utf-8"))
app = src["apps"][0]
v = {"version": version, "buildVersion": build, "date": datetime.date.today().isoformat(),
     "localizedDescription": f"BlueScreen {version} (build {build}).", "downloadURL": url, "size": size, "minOSVersion": "16.0"}
app["versions"] = [v] + [x for x in app.get("versions", []) if not (x.get("version") == version and x.get("buildVersion") == build)][:9]
# anciens champs encore lus par les vieilles versions d'AltStore
app.update({"version": version, "versionDate": v["date"], "versionDescription": v["localizedDescription"], "downloadURL": url, "size": size})
json.dump(src, open(p, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
print("source mise à jour :", version, build, size)
