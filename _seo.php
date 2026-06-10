<?php
/* One-off: inject SEO meta (title, description, canonical, Open Graph, Twitter, JSON-LD)
   into every page. Uses the token __SITE_URL__ which set-site-url.ps1 replaces later.
   Run once, then this file is deleted. */
$dir = __DIR__;
$SITE = '__SITE_URL__';
$OG = $SITE . '/assets/img/og-image.png';

$meta = [
  'index.html'        => ['GarbageP2P — Sell & Buy Scrap Online in Pakistan | P2P Recycling Marketplace',
    "Sell your scrap directly to buyers or buy recyclables at top rates on GarbageP2P — Pakistan's peer-to-peer scrap marketplace. Set your own price, negotiate and see live scrap rates."],
  'marketplace.html'  => ['Scrap Marketplace — Buy & Sell Trash Near You | GarbageP2P',
    'Browse live buy and sell requests for plastic, iron, copper, paper and e-waste. Find scrap collectors and dealers near you on the map and negotiate your price.'],
  'deals.html'        => ['Live Scrap Deals & Average Prices in Pakistan | GarbageP2P',
    'See recently closed scrap deals and recency-weighted average prices per kg for every material. Full transparency on what scrap really sells for in Pakistan.'],
  'rates.html'        => ["Today's Scrap Rates in Pakistan (PKR per kg) | GarbageP2P",
    "Live scrap rates for iron, copper, aluminium, plastic, paper, e-waste and more, updated from real recent deals. Check today's kabari rates before you sell."],
  'post-request.html' => ['Post a Scrap Request — Sell or Buy Scrap Free | GarbageP2P',
    'List scrap you want to sell or post what you want to buy. Add your price, photos, live location and pickup point — free on GarbageP2P.'],
  'book-pickup.html'  => ['Book a Free Doorstep Scrap Pickup | GarbageP2P',
    'Schedule a doorstep scrap pickup in minutes. Choose a date and time slot — our team weighs on calibrated scales and pays on the spot.'],
  'about.html'        => ["About GarbageP2P — Pakistan's P2P Scrap & Recycling Marketplace",
    'GarbageP2P connects waste collectors, sweepers and sorters directly with scrap dealers and recyclers for fair, transparent prices — no middlemen.'],
  'contact.html'      => ['Contact GarbageP2P — Support, Dealer & Recycler Partnerships',
    'Get in touch with GarbageP2P for support, dealership and recycling partnership enquiries. Based in Karachi, serving all of Pakistan.'],
  'request.html'      => ['Scrap Request Details | GarbageP2P',
    'View a scrap buy or sell request with live and pickup locations on the map, then negotiate the price directly with the other party.'],
  'dashboard.html'    => ['My Activity — Requests, Deals & Pickups | GarbageP2P',
    'Track your posted scrap requests, closed deals and pickup bookings on GarbageP2P.'],
  'profile.html'      => ['Your Profile | GarbageP2P',
    'Set up your free GarbageP2P profile to start buying and selling scrap across Pakistan.'],
];

function attr($s) { return htmlspecialchars($s, ENT_QUOTES, 'UTF-8'); }

foreach ($meta as $file => $info) {
  $path = $dir . '/' . $file;
  if (!is_file($path)) { echo "missing $file\n"; continue; }
  $html = file_get_contents($path);
  if (strpos($html, '<!-- SEO:GP2P -->') !== false) { echo "skip $file (already done)\n"; continue; }

  [$title, $desc] = $info;
  $t = attr($title); $d = attr($desc); $url = $SITE . '/' . $file;

  // optimised <title>
  $html = preg_replace('/<title>.*?<\/title>/s', '<title>' . attr($title) . '</title>', $html, 1);
  // drop any existing description meta to avoid duplicates
  $html = preg_replace('/[ \t]*<meta name="description"[^>]*>\R?/i', '', $html);

  $block  = "<!-- SEO:GP2P -->\n";
  $block .= "<meta name=\"description\" content=\"$d\">\n";
  $block .= "<link rel=\"canonical\" href=\"$url\">\n";
  $block .= "<meta name=\"robots\" content=\"index, follow\">\n";
  $block .= "<meta name=\"author\" content=\"GarbageP2P\">\n";
  $block .= "<meta name=\"theme-color\" content=\"#15633e\">\n";
  $block .= "<meta name=\"geo.region\" content=\"PK\">\n";
  $block .= "<meta name=\"geo.placename\" content=\"Karachi, Pakistan\">\n";
  $block .= "<meta property=\"og:type\" content=\"website\">\n";
  $block .= "<meta property=\"og:site_name\" content=\"GarbageP2P\">\n";
  $block .= "<meta property=\"og:locale\" content=\"en_PK\">\n";
  $block .= "<meta property=\"og:title\" content=\"$t\">\n";
  $block .= "<meta property=\"og:description\" content=\"$d\">\n";
  $block .= "<meta property=\"og:url\" content=\"$url\">\n";
  $block .= "<meta property=\"og:image\" content=\"$OG\">\n";
  $block .= "<meta property=\"og:image:width\" content=\"1200\">\n";
  $block .= "<meta property=\"og:image:height\" content=\"630\">\n";
  $block .= "<meta name=\"twitter:card\" content=\"summary_large_image\">\n";
  $block .= "<meta name=\"twitter:title\" content=\"$t\">\n";
  $block .= "<meta name=\"twitter:description\" content=\"$d\">\n";
  $block .= "<meta name=\"twitter:image\" content=\"$OG\">\n";

  if ($file === 'index.html') {
    $ld = [
      '@context' => 'https://schema.org',
      '@graph' => [
        [
          '@type' => 'Organization', '@id' => $SITE . '/#org', 'name' => 'GarbageP2P',
          'url' => $SITE . '/', 'logo' => $OG,
          'description' => 'Pakistan\'s peer-to-peer scrap and recycling marketplace connecting waste collectors with dealers and recyclers.',
          'areaServed' => 'PK', 'email' => 'support@garbagep2p.pk',
        ],
        [
          '@type' => 'WebSite', '@id' => $SITE . '/#website', 'url' => $SITE . '/',
          'name' => 'GarbageP2P', 'inLanguage' => 'en-PK',
          'publisher' => ['@id' => $SITE . '/#org'],
          'potentialAction' => [
            '@type' => 'SearchAction',
            'target' => ['@type' => 'EntryPoint', 'urlTemplate' => $SITE . '/marketplace.html?q={search_term_string}'],
            'query-input' => 'required name=search_term_string',
          ],
        ],
      ],
    ];
    $block .= "<script type=\"application/ld+json\">\n"
      . json_encode($ld, JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT) . "\n</script>\n";
  }

  $html = preg_replace('/<\/head>/', $block . '</head>', $html, 1);
  file_put_contents($path, $html);
  echo "done $file\n";
}
echo "SEO injection complete.\n";
