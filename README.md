# obsidian-scrape-htb-info
PowerShell script to scrape Hack The Box machine OS, difficulty, and image, and import into an Obsidian note's YAML frontmatter.

Built for use with the "Shell commands" community plugin, ex:

```ps1
./update_htb_info_and_image.ps1 {{title}} {{file_path:absolute}} <replace_with_path_to_location_of_obsidian_assets_folder>
```