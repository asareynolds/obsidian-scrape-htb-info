# obsidian-scrape-htb-info
PowerShell script to scrape Hack The Box machine OS, difficulty, and image, and import into an Obsidian note's YAML frontmatter.
Accepts three arguments: box name, absolute path of Markdown file, absolute path of Obsidian assets folder

Built for use with the "Shell commands" community plugin, ex:

```ps1
./update_htb_info_and_image.ps1 {{title}} {{file_path:absolute}} <replace_with_path_to_location_of_obsidian_assets_folder>
```

Designed to work with the following YAML attributes:

Example pre-fill:
```
---
_image:
_os:
_difficulty:
---
```

Example post-fill:
```
---
_image: "[[htb_active.png]]"
_os: windows
_difficulty: easy
---
```
