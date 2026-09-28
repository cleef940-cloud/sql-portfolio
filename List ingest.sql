# ingest/core/list_ingest.py — DISCOVERY ONLY (Dec 2025)
import asyncio
import re
from typing import List, Dict
from urllib.parse import urljoin

import aiohttp
from loguru import logger

from ingest.core.rss_ingest import normalize_url  # reuse shared normalizer
from store.url_registry import URLRegistryDB


async def discover_from_html_list(
    session: aiohttp.ClientSession,
    source_name: str,
    source_rules: Dict,
    registry: URLRegistryDB,
    stats: Dict[str, int]
) -> List[Dict]:
    """
    Discovery-only: extract candidate URLs from list pages → register in DB
    No article fetching, no full page parsing beyond list extraction
    """
    discovered = []

    base_url = source_rules["base_url"]
    list_selector = source_rules.get("list_selector")
    link_selector = source_rules.get("link_selector") or source_rules.get("title_selector")

    if not list_selector or not link_selector:
        logger.error(f"{source_name} → missing selectors")
        stats["failed"] += 1
        return []

    try:
        timeout = aiohttp.ClientTimeout(total=15)
        async with session.get(base_url, timeout=timeout) as resp:
            if resp.status != 200:
                logger.warning(f"{source_name} → HTTP {resp.status}")
                stats["failed"] += 1
                return []
            html = await resp.text()
            stats["fetched"] += 1

    except Exception as e:
        logger.warning(f"{source_name} → fetch failed → {e}")
        stats["failed"] += 1
        return []

    try:
        from selectolax.parser import HTMLParser
        tree = HTMLParser(html)
        items = tree.css(list_selector)

        if not items and (fallback := source_rules.get("fallback_list_selector")):
            logger.debug(f"{source_name} → using fallback selector")
            items = tree.css(fallback)

        if not items:
            logger.warning(f"{source_name} → no items found")
            stats["skipped"] += 1
            return []

        logger.info(f"{source_name} → {len(items)} potential items")

        max_per_page = source_rules.get("max_per_page", 80)

        for item in items[:max_per_page]:
            try:
                link_node = item.css_first(link_selector)
                if not link_node:
                    continue

                raw_href = link_node.attributes.get("href", "").strip()
                if not raw_href:
                    continue

                full_url = urljoin(base_url, raw_href)
                canonical_url = normalize_url(full_url)

                # Early cheap junk filter
                if any(x in canonical_url.lower() for x in ["/tag/", "/category/", "/author/", "/page/", "/video/", "/live/", "/amp/"]):
                    continue

                if "url_pattern" in source_rules and not re.search(source_rules["url_pattern"], canonical_url):
                    continue

                # Register → the registry computes canonical_id and handles deduplication
                entry = registry.register_url(
                    url=full_url,
                    canonical_url=canonical_url,
                    source=source_name
                )

                discovered.append({
                    "canonical_id": entry.canonical_id,
                    "canonical_url": entry.canonical_url,
                    "source": source_name,
                    "first_seen": entry.first_seen.isoformat()
                })

                stats["discovered"] += 1

            except Exception as e:
                logger.debug(f"{source_name} → item failed → {e}")
                stats["skipped"] += 1
                continue

        if throttle := source_rules.get("throttle", 0.0):
            await asyncio.sleep(throttle)

        return discovered

    except Exception as e:
        logger.error(f"{source_name} → parsing failed → {e}")
        stats["failed"] += 1
        return []


async def ingest_html_list_sources(
    sources: List[Dict],
    registry: URLRegistryDB,
    concurrency: int = 6
) -> tuple[List[Dict], Dict[str, int]]:
    """
    Main entry point — similar shape to rss_ingest
    """
    overall_stats = {
        "fetched": 0,
        "discovered": 0,
        "skipped": 0,
        "failed": 0
    }

    all_discovered = []

    connector = aiohttp.TCPConnector(limit=concurrency)
    async with aiohttp.ClientSession(connector=connector) as session:
        tasks = []

        for rule in sources:
            tasks.append(
                discover_from_html_list(
                    session=session,
                    source_name=rule["name"],
                    source_rules=rule,
                    registry=registry,
                    stats=overall_stats
                )
            )

        results = await asyncio.gather(*tasks, return_exceptions=True)

        for result in results:
            if isinstance(result, Exception):
                overall_stats["failed"] += 1
                continue
            all_discovered.extend(result)

    return all_discovered, overall_stats
