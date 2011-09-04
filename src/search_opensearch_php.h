"<script language=\"PHP\">\n"
"require \"search-functions.php\";\n"
"\n"
"$mode = array_key_exists('v', $_GET)?$_GET['v']:\"\";\n"
"$query = array_key_exists('query', $_GET)?$_GET['query']:\"\";\n"
"\n"
"$query_results = run_query($query);\n"
"\n"
"switch ($mode)\n"
"{\n"
"  case \"opensearch.xml\":\n"
"    opensearch_description();\n"
"    break;\n"
"  case \"json\":\n"
"    opensearch_json_results($query, $query_results);\n"
"    break;\n"
"  case \"xml\":\n"
"    opensearch_xml_results($query, $query_results);\n"
"    break;\n"
"  default:\n"
"    invalid_format($query, $query_results);\n"
"    break;\n"
"}\n"
"\n"
"function opensearch_description()\n"
"{\n"
"  global $config;\n"
"  global $translator;\n"
"\n"
"  $shortname = $translator['search'].\" \".$config['PROJECT_NAME'];\n"
"  $link = \"http://\".$_SERVER['HTTP_HOST'].dirname($_SERVER['SCRIPT_NAME']);\n"
"  header(\"Content-Type: application/xml\");\n"
"  echo <<<END_OPENSEARCH\n"
"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
"<OpenSearchDescription xmlns=\"http://a9.com/-/spec/opensearch/1.1/\">\n"
"<ShortName>$shortname</ShortName>\n"
"<Description>Doxygen Search</Description>\n"
"<InputEncoding>UTF-8</InputEncoding>\n"
"<!--\n"
"<Image height=\"16\" width=\"16\" type=\"image/x-icon\">\n"
"http://dev.squello.com/doc/html/favicon.ico</Image>\n"
"-->\n"
"<Url type=\"text/html\" method=\"GET\"\n"
"template=\"$link/search.php?query={searchTerms}\" />\n"
"<Url type=\"application/x-suggestions+json\" method=\"GET\"\n"
"template=\"$link/search-opensearch.php?v=json&amp;query={searchTerms}\" />\n"
"<Url type=\"application/x-suggestions+xml\" method=\"GET\"\n"
"template=\"$link/search-opensearch.php?v=xml&amp;query={searchTerms}\" />\n"
"</OpenSearchDescription>\n"
"END_OPENSEARCH;\n"
"}\n"
"\n"
"function opensearch_xml_results($query, array $results)\n"
"{\n"
"  // Much as I hate copy'n'paste code re-use, this is for testing;\n"
"  // I expect a richer version to come soon.\n"
"  // Although I hate that IE does this richer than FF more...\n"
"  $qs_results = array();\n"
"  foreach ($results as $i => $val)\n"
"  {\n"
"    foreach ($val['words'] as $j => $word)\n"
"    {\n"
"      if (array_key_exists($word, $qs_results))\n"
"        $qs_results[$word['match']]++;\n"
"      else\n"
"        $qs_results[$word['match']] = 1;\n"
"    }\n"
"  }\n"
"  $result = <<<END_FRAG\n"
"<?xml version=\"1.0\"?>\n"
"<SearchSuggestion xmlns=\"http://schemas.microsoft.com/Search/2008/suggestions\">\n"
"<Query>$query</Query>\n"
"<Section>\n"
"END_FRAG;\n"
"  foreach ($qs_results as $word => $count)\n"
"  {\n"
"    $result .= <<<END_FRAG\n"
"<Item>\n"
"<Text>$word</Text>\n"
"<Description>$count results</Description>\n"
"</Item>\n"
"END_FRAG;\n"
"  }\n"
"  $result .= <<<END_FRAG\n"
"</Section>\n"
"</SearchSuggestion>\n"
"END_FRAG;\n"
"  echo $result;\n"
"}\n"
"\n"
"function opensearch_json_results($query, array $results)\n"
"{\n"
"  $qs_results = array();\n"
"  foreach ($results as $i => $val)\n"
"  {\n"
"    foreach ($val['words'] as $j => $word)\n"
"    {\n"
"      if (array_key_exists($word, $qs_results))\n"
"        $qs_results[$word['match']]++;\n"
"      else\n"
"        $qs_results[$word['match']] = 1;\n"
"    }\n"
"  }\n"
"  $result = '[\"'.$query.'\", [';\n"
"  $json_words = \"\";\n"
"  $json_descriptions = \"\";\n"
"  $i = 0;\n"
"  foreach ($qs_results as $word => $count)\n"
"  {\n"
"    if ($i != 0)\n"
"    {\n"
"      $json_words .= \", \";\n"
"      $json_descriptions .= \", \";\n"
"    }\n"
"    $json_words .= '\"'.$word.'\"';\n"
"    $json_descriptions .= '\"'.$count.' result'.($count==1?'':'s').'\"';\n"
"    $i++;\n"
"  }\n"
"  print \"[\\\"$query\\\", [$json_words],[$json_descriptions]]\";\n"
"}\n"
"\n"
"function invalid_format($query, array $results)\n"
"{\n"
"  print \"Search results for '$query':\\n\\n\";\n"
"  print_r($results);\n"
"}\n"
"</script>\n"
"<script language=\"PHP\">\n"
"require \"search-functions.php\";\n"
"\n"
"$mode = array_key_exists('v', $_GET)?$_GET['v']:\"\";\n"
"$query = array_key_exists('query', $_GET)?$_GET['query']:\"\";\n"
"\n"
"$query_results = run_query($query);\n"
"\n"
"switch ($mode)\n"
"{\n"
"  case \"opensearch.xml\":\n"
"    opensearch_description();\n"
"    break;\n"
"  case \"json\":\n"
"    opensearch_json_results($query, $query_results);\n"
"    break;\n"
"  case \"xml\":\n"
"    opensearch_xml_results($query, $query_results);\n"
"    break;\n"
"  default:\n"
"    invalid_format($query, $query_results);\n"
"    break;\n"
"}\n"
"\n"
"function opensearch_description()\n"
"{\n"
"  global $config;\n"
"  global $translator;\n"
"\n"
"  $shortname = $translator['search'].\" \".$config['PROJECT_NAME'];\n"
"  $link = \"http://\".$_SERVER['HTTP_HOST'].dirname($_SERVER['SCRIPT_NAME']);\n"
"  header(\"Content-Type: application/xml\");\n"
"  echo <<<END_OPENSEARCH\n"
"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
"<OpenSearchDescription xmlns=\"http://a9.com/-/spec/opensearch/1.1/\">\n"
"<ShortName>$shortname</ShortName>\n"
"<Description>Doxygen Search</Description>\n"
"<InputEncoding>UTF-8</InputEncoding>\n"
"<!--\n"
"<Image height=\"16\" width=\"16\" type=\"image/x-icon\">\n"
"http://dev.squello.com/doc/html/favicon.ico</Image>\n"
"-->\n"
"<Url type=\"text/html\" method=\"GET\"\n"
"template=\"$link/search.php?query={searchTerms}\" />\n"
"<Url type=\"application/x-suggestions+json\" method=\"GET\"\n"
"template=\"$link/search-opensearch.php?v=json&amp;query={searchTerms}\" />\n"
"<Url type=\"application/x-suggestions+xml\" method=\"GET\"\n"
"template=\"$link/search-opensearch.php?v=xml&amp;query={searchTerms}\" />\n"
"</OpenSearchDescription>\n"
"END_OPENSEARCH;\n"
"}\n"
"\n"
"function opensearch_xml_results($query, array $results)\n"
"{\n"
"  // Much as I hate copy'n'paste code re-use, this is for testing;\n"
"  // I expect a richer version to come soon.\n"
"  // Although I hate that IE does this richer than FF more...\n"
"  $qs_results = array();\n"
"  foreach ($results as $i => $val)\n"
"  {\n"
"    foreach ($val['words'] as $j => $word)\n"
"    {\n"
"      if (array_key_exists($word, $qs_results))\n"
"        $qs_results[$word['match']]++;\n"
"      else\n"
"        $qs_results[$word['match']] = 1;\n"
"    }\n"
"  }\n"
"  $result = <<<END_FRAG\n"
"<?xml version=\"1.0\"?>\n"
"<SearchSuggestion xmlns=\"http://schemas.microsoft.com/Search/2008/suggestions\">\n"
"<Query>$query</Query>\n"
"<Section>\n"
"END_FRAG;\n"
"  foreach ($qs_results as $word => $count)\n"
"  {\n"
"    $result .= <<<END_FRAG\n"
"<Item>\n"
"<Text>$word</Text>\n"
"<Description>$count results</Description>\n"
"</Item>\n"
"END_FRAG;\n"
"  }\n"
"  $result .= <<<END_FRAG\n"
"</Section>\n"
"</SearchSuggestion>\n"
"END_FRAG;\n"
"  echo $result;\n"
"}\n"
"\n"
"function opensearch_json_results($query, array $results)\n"
"{\n"
"  $qs_results = array();\n"
"  foreach ($results as $i => $val)\n"
"  {\n"
"    foreach ($val['words'] as $j => $word)\n"
"    {\n"
"      if (array_key_exists($word, $qs_results))\n"
"        $qs_results[$word['match']]++;\n"
"      else\n"
"        $qs_results[$word['match']] = 1;\n"
"    }\n"
"  }\n"
"  $result = '[\"'.$query.'\", [';\n"
"  $json_words = \"\";\n"
"  $json_descriptions = \"\";\n"
"  $i = 0;\n"
"  foreach ($qs_results as $word => $count)\n"
"  {\n"
"    if ($i != 0)\n"
"    {\n"
"      $json_words .= \", \";\n"
"      $json_descriptions .= \", \";\n"
"    }\n"
"    $json_words .= '\"'.$word.'\"';\n"
"    $json_descriptions .= '\"'.$count.' result'.($count==1?'':'s').'\"';\n"
"    $i++;\n"
"  }\n"
"  print \"[\\\"$query\\\", [$json_words],[$json_descriptions]]\";\n"
"}\n"
"\n"
"function invalid_format($query, array $results)\n"
"{\n"
"  print \"Search results for '$query':\\n\\n\";\n"
"  print_r($results);\n"
"}\n"
"</script>\n"
