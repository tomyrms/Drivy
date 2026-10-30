#!/usr/bin/env python3
"""Activate Drivy's private GitHub Project via an authenticated GitHub CLI.

Default: print a local plan only. --apply creates/reuses metadata, never issues.
Requires Python 3.10+ and gh with the project scope. No token is stored here.
Official schema: https://docs.github.com/en/graphql/reference/projects
"""
from __future__ import annotations
import argparse
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

BASE = Path(__file__).resolve().parent
COLORS = {"Backlog": "GRAY", "Prêt": "BLUE", "En cours": "YELLOW",
          "À tester par Tomas": "ORANGE", "Tests et validation": "PURPLE",
          "Bloqué": "RED", "Terminé": "GREEN", "Idée": "GRAY",
          "À étudier": "ORANGE", "Cadré": "BLUE", "Prêt à découper": "GREEN",
          "En développement": "YELLOW", "Initiative": "PURPLE", "Issue": "BLUE",
          "P0": "RED", "P1": "ORANGE", "P2": "YELLOW", "P3": "GRAY"}
FIELD_FRAGMENT = """__typename
... on ProjectV2Field { id name dataType }
... on ProjectV2SingleSelectField { id name dataType options { id name color description } }
... on ProjectV2IterationField { id name dataType }"""
ITEM_FRAGMENT = """id isArchived content { __typename
... on DraftIssue { id title body }
... on Issue { id number url repository { nameWithOwner } } }
fieldValues(first:100) { nodes { ... on ProjectV2ItemFieldSingleSelectValue {
name field { ... on ProjectV2SingleSelectField { id } } } } pageInfo { hasNextPage } }"""

def gh(*args: str, payload: dict | None = None) -> dict | list:
    proc = subprocess.run(["gh", *args], input=None if payload is None else json.dumps(payload),
                          text=True, encoding="utf-8", capture_output=True, timeout=120)
    if proc.returncode:
        # Do not print responses, environment or potential credentials.
        raise RuntimeError("GitHub CLI a refusé l'opération. Vérifier gh auth status, le compte tomyrms et les droits project. Aucune réponse privée affichée.")
    result = json.loads(proc.stdout)
    if isinstance(result, dict) and result.get("errors"):
        raise RuntimeError("Erreur GraphQL : vérifier les permissions et le schéma Projects. Reprise possible sans recréer les éléments déjà présents.")
    return result

def gql(query: str, **variables) -> dict:
    return gh("api", "graphql", "--input", "-", payload={"query": query, "variables": variables})["data"]

def mutate(name: str, input_type: str, values: dict, selection: str) -> dict:
    return gql(f"mutation($input:{input_type}!) {{ {name}(input:$input) {{ {selection} }} }}", input=values)[name]

def paginate(query: str, extract, **variables) -> list:
    result, cursor = [], None
    while True:
        connection = extract(gql(query, after=cursor, **variables))
        result.extend(node for node in connection["nodes"] if node is not None)
        info = connection["pageInfo"]
        if not info["hasNextPage"]:
            return result
        if not info.get("endCursor") or info["endCursor"] == cursor:
            raise RuntimeError("Pagination incomplète : aucune liste partielle déclarée complète.")
        cursor = info["endCursor"]

def fields(project_id: str) -> dict:
    query = "query($id:ID!,$after:String){ node(id:$id){ ... on ProjectV2 { fields(first:100,after:$after){ nodes{" + FIELD_FRAGMENT + "} pageInfo{hasNextPage endCursor} } } } }"
    rows = paginate(query, lambda d: d["node"]["fields"], id=project_id)
    names = [x["name"] for x in rows]
    if len(names) != len(set(names)):
        raise RuntimeError("Champs homonymes : résoudre l'ambiguïté dans Projects avant reprise.")
    return {row["name"]: row for row in rows}

def items(project_id: str) -> list:
    query = "query($id:ID!,$after:String){ node(id:$id){ ... on ProjectV2 { items(first:100,after:$after){ nodes{" + ITEM_FRAGMENT + "} pageInfo{hasNextPage endCursor} } } } }"
    rows = paginate(query, lambda d: d["node"]["items"], id=project_id)
    if any(x["fieldValues"]["pageInfo"]["hasNextPage"] for x in rows):
        raise RuntimeError("Plus de 100 valeurs sur une carte : ne pas modifier un état partiellement lu.")
    return rows

def option(name: str) -> dict:
    return {"name": name, "color": COLORS.get(name, "GRAY"), "description": ""}

def ensure_field(project_id: str, spec: dict, fresh: bool = False) -> None:
    current = fields(project_id).get(spec["name"])
    wanted = spec.get("options", [])
    if current is None:
        data = {"projectId": project_id, "name": spec["name"], "dataType": spec["type"]}
        if wanted:
            data["singleSelectOptions"] = [option(x) for x in wanted]
        mutate("createProjectV2Field", "CreateProjectV2FieldInput", data,
               "projectV2Field { ... on ProjectV2Field { id } ... on ProjectV2SingleSelectField { id } }")
    elif current["dataType"] != spec["type"]:
        raise RuntimeError("Type incompatible pour le champ " + spec["name"])
    elif wanted:
        old = current["options"]
        # Preserve option IDs and existing values. Only replace empty fresh defaults.
        missing = [name for name in wanted if name not in {x["name"] for x in old}]
        if fresh or missing:
            merged = [option(x) for x in wanted] if fresh else old + [option(x) for x in missing]
            mutate("updateProjectV2Field", "UpdateProjectV2FieldInput",
                   {"fieldId": current["id"], "singleSelectOptions": merged},
                   "projectV2Field { ... on ProjectV2SingleSelectField { id } }")

def set_missing(project_id: str, item: dict, registry: dict, values: dict) -> None:
    existing = {v["field"]["id"] for v in item.get("fieldValues", {}).get("nodes", []) if v.get("field")}
    for name, value in values.items():
        field = registry[name]
        if field["id"] in existing:
            continue
        matches = [o for o in field["options"] if o["name"] == value]
        if len(matches) != 1:
            raise RuntimeError("Option manquante ou ambiguë : " + name)
        mutate("updateProjectV2ItemFieldValue", "UpdateProjectV2ItemFieldValueInput",
               {"projectId": project_id, "itemId": item["id"], "fieldId": field["id"],
                "value": {"singleSelectOptionId": matches[0]["id"]}}, "projectV2Item { id }")

def initiative_body(roadmap: str, key: str) -> str:
    match = re.search(r"^## " + re.escape(key) + r" — [^\n]*\n(.*?)(?=^## |\Z)", roadmap, re.M | re.S)
    if not match:
        raise RuntimeError("Initiative absente de ROADMAP.md : " + key)
    return (f"<!-- drivy-roadmap:{key} -->\n\n**Idée à cadrer, pas une autorisation de développement.**\n\n"
            + match.group(1).strip())

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="Créer/rattacher les métadonnées distantes")
    args = parser.parse_args()
    cfg = json.loads((BASE / "project.json").read_text(encoding="utf-8"))
    roadmap = (BASE / cfg["roadmap_file"]).read_text(encoding="utf-8")
    if cfg["owner"] != "tomyrms" or cfg["repository"] != "tomyrms/Drivy" or not cfg["private"]:
        raise RuntimeError("Cible ou confidentialité inattendue.")
    bodies = {x["id"]: initiative_body(roadmap, x["id"]) for x in cfg["initiatives"]}
    if not args.apply:
        print("PLAN SEULEMENT — aucune lecture ou écriture distante.")
        print(cfg["title"] + " (privé) : cinq brouillons, sept statuts, champs et quatre vues.")
        for row in cfg["initiatives"]:
            print(row["id"] + " : " + row["title"])
        print("Importer les issues ouvertes existantes, sans créer ni rouvrir d'issue.")
        print("Préserver les cartes, choix, priorités, dates et statuts existants. Puis vérifier les réglages visuels dans GitHub.")
        print("Activation : python docs/product/setup_project.py --apply")
        return
    if not shutil.which("gh"):
        raise RuntimeError("Installer GitHub CLI, puis gh auth login et gh auth refresh -s project.")
    if gql("query { viewer { login } }")["viewer"]["login"].lower() != cfg["owner"].lower():
        raise RuntimeError("Le compte GitHub CLI actif doit être tomyrms.")
    query = "query($owner:String!,$after:String){ user(login:$owner){ projectsV2(first:100,after:$after){ nodes{id number title url public closed} pageInfo{hasNextPage endCursor} } } }"
    projects = paginate(query, lambda d: d["user"]["projectsV2"], owner=cfg["owner"])
    matches = [p for p in projects if p["title"] == cfg["title"]]
    if len(matches) > 1:
        raise RuntimeError("Plusieurs projets du même nom : les distinguer avant de relancer.")
    identity = gql("query { user(login:\"tomyrms\"){id} repository(owner:\"tomyrms\",name:\"Drivy\"){id} }")
    created = not matches
    if created:
        project = mutate("createProjectV2", "CreateProjectV2Input",
                         {"ownerId": identity["user"]["id"], "repositoryId": identity["repository"]["id"], "title": cfg["title"]},
                         "projectV2 { id number title url public closed }")["projectV2"]
        mutate("updateProjectV2", "UpdateProjectV2Input",
               {"projectId": project["id"], "public": False, "shortDescription": cfg["description"]}, "projectV2 { id public }")
    else:
        project = matches[0]
        if project["public"] or project["closed"]:
            raise RuntimeError("Projet existant public ou fermé : aucun changement de visibilité ou réouverture implicite.")
    pid = project["id"]
    print("Projet ciblé : " + project["url"])
    # Read-back before adding any draft or repository data.
    privacy = gql("query($id:ID!){ node(id:$id){ ... on ProjectV2 { public } } }", id=pid)["node"]
    if privacy["public"]:
        raise RuntimeError("Confidentialité privée non confirmée.")
    mutate("linkProjectV2ToRepository", "LinkProjectV2ToRepositoryInput",
           {"projectId": pid, "repositoryId": identity["repository"]["id"]}, "repository { id }")
    ensure_field(pid, {"name": "Status", "type": "SINGLE_SELECT", "options": cfg["status_options"]}, fresh=created and not items(pid))
    for spec in cfg["fields"]:
        ensure_field(pid, spec)
    registry, cards = fields(pid), items(pid)
    for initiative in cfg["initiatives"]:
        marker = "<!-- drivy-roadmap:" + initiative["id"] + " -->"
        matches = [x for x in cards if (x.get("content") or {}).get("__typename") == "DraftIssue"
                   and (marker in x["content"].get("body", "") or x["content"]["title"] == initiative["title"])]
        if len(matches) > 1:
            raise RuntimeError("Brouillons homonymes : " + initiative["id"])
        if matches:
            item = matches[0]
            if item["isArchived"]:
                print(initiative["id"] + " : archive conservée, pas de doublon")
                continue
        else:
            item = mutate("addProjectV2DraftIssue", "AddProjectV2DraftIssueInput",
                          {"projectId": pid, "title": initiative["title"], "body": bodies[initiative["id"]]},
                          "projectItem { id }")["projectItem"]
        set_missing(pid, item, registry, {"Nature": "Initiative", "Maturité": initiative["maturity"],
                                         "Horizon": "À définir", "Effort": "À estimer", "Status": "Backlog"})
    indexed = {x["content"]["id"]: x for x in cards if x.get("content") and x["content"].get("__typename") == "Issue"}
    imported, page = [], 1
    while True:
        batch = gh("api", f"repos/{cfg['repository']}/issues?state=open&per_page=100&page={page}")
        for issue in batch:
            if "pull_request" in issue or issue["number"] in cfg["excluded_issue_numbers"]:
                continue
            item = indexed.get(issue["node_id"])
            if item and item["isArchived"]:
                continue
            if item is None:
                item = mutate("addProjectV2ItemById", "AddProjectV2ItemByIdInput",
                              {"projectId": pid, "contentId": issue["node_id"]}, "item { id }")["item"]
            values = {"Nature": "Issue", "Status": "Backlog"}
            if issue["number"] in (45, 63):
                values.update({"Maturité": "Idée", "Horizon": "Plus tard"})
            set_missing(pid, item, registry, values)
            imported.append(issue["node_id"])
        if len(batch) < 100:
            break
        page += 1
    view_query = "query($id:ID!,$after:String){ node(id:$id){ ... on ProjectV2 { views(first:100,after:$after){ nodes{id name layout filter} pageInfo{hasNextPage endCursor} } } } }"
    views = paginate(view_query, lambda d: d["node"]["views"], id=pid)
    for spec in cfg["views"]:
        if any(v["name"] == spec["name"] for v in views):
            continue  # Do not overwrite a user's view layout or filters.
        view = mutate("createProjectV2View", "CreateProjectV2ViewInput",
                      {"projectId": pid, "name": spec["name"], "layout": spec["layout"]},
                      "projectV2View { id }")["projectV2View"]
        mutate("updateProjectV2View", "UpdateProjectV2ViewInput",
               {"viewId": view["id"], "filter": spec["filter"]}, "projectV2View { id }")
    final = items(pid)
    known = {x["content"]["id"] for x in final if x.get("content")}
    if not set(imported).issubset(known):
        raise RuntimeError("La relecture ne confirme pas toutes les cartes importées.")
    final_views = paginate(view_query, lambda d: d["node"]["views"], id=pid)
    if not {v["name"] for v in cfg["views"]}.issubset({v["name"] for v in final_views}):
        raise RuntimeError("Vues manquantes après relecture.")
    for initiative in cfg["initiatives"]:
        marker = "<!-- drivy-roadmap:" + initiative["id"] + " -->"
        if not any((x.get("content") or {}).get("__typename") == "DraftIssue" and
                   (marker in x["content"].get("body", "") or x["content"]["title"] == initiative["title"])
                   for x in final):
            raise RuntimeError("Brouillon manquant après relecture : " + initiative["id"])
    print(f"Métadonnées relues : {len(imported)} issues existantes rattachées ; aucune issue créée.")
    print("Projet : " + project["url"])
    print("À vérifier dans GitHub : Développement groupé par Status ; Roadmap avec Début cible/Fin cible.")
    print("Ne pas ajouter de dates fictives. Ne pas activer de clôture automatique. Les statuts restent à trier, pas présumés en cours.")

if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, ValueError, KeyError, subprocess.TimeoutExpired) as exc:
        print("ARRÊT : " + str(exc), file=sys.stderr)
        print("Les écritures déjà réussies restent en place ; relancer après correction, sans supprimer le projet.", file=sys.stderr)
        sys.exit(1)
