defmodule SmallSdk.XMetadata do
  @moduledoc false

  @default_api_base_url "https://x.com"
  @default_bearer_token "AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA"
  @default_tweet_result_query_id "8CEYnZhCp0dx9DFyyEBlbQ"

  @feature_switches [
    "creator_subscriptions_tweet_preview_api_enabled",
    "premium_content_api_read_enabled",
    "communities_web_enable_tweet_community_results_fetch",
    "c9s_tweet_anatomy_moderator_badge_enabled",
    "responsive_web_grok_analyze_button_fetch_trends_enabled",
    "responsive_web_grok_analyze_post_followups_enabled",
    "rweb_cashtags_composer_attachment_enabled",
    "responsive_web_jetfuel_frame",
    "responsive_web_grok_share_attachment_enabled",
    "responsive_web_grok_annotations_enabled",
    "articles_preview_enabled",
    "responsive_web_edit_tweet_api_enabled",
    "rweb_conversational_replies_downvote_enabled",
    "graphql_is_translatable_rweb_tweet_is_translatable_enabled",
    "view_counts_everywhere_api_enabled",
    "longform_notetweets_consumption_enabled",
    "responsive_web_twitter_article_tweet_consumption_enabled",
    "content_disclosure_indicator_enabled",
    "content_disclosure_ai_generated_indicator_enabled",
    "responsive_web_grok_show_grok_translated_post",
    "responsive_web_grok_analysis_button_from_backend",
    "post_ctas_fetch_enabled",
    "rweb_cashtags_enabled",
    "freedom_of_speech_not_reach_fetch_enabled",
    "standardized_nudges_misinfo",
    "tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled",
    "longform_notetweets_rich_text_read_enabled",
    "longform_notetweets_inline_media_enabled",
    "profile_label_improvements_pcf_label_in_post_enabled",
    "responsive_web_profile_redirect_enabled",
    "rweb_tipjar_consumption_enabled",
    "verified_phone_label_enabled",
    "responsive_web_grok_image_annotation_enabled",
    "responsive_web_grok_imagine_annotation_enabled",
    "responsive_web_grok_community_note_auto_translation_is_enabled",
    "responsive_web_graphql_skip_user_profile_image_extensions_enabled",
    "responsive_web_graphql_timeline_navigation_enabled"
  ]

  @field_toggles [
    "withArticleRichContentState",
    "withArticlePlainText",
    "withArticleSummaryText",
    "withArticleVoiceOver",
    "withGrokAnalyze",
    "withDisallowedReplyControls",
    "withPayments",
    "withAuxiliaryUserLabels"
  ]

  def get_metadata(url) when is_binary(url) do
    with {:ok, tweet_id} <- tweet_id(url),
         {:ok, cookie} <- twitter_cookie(),
         {:ok, csrf_token} <- csrf_token(cookie),
         {:ok, body} <- fetch_tweet_result(url, tweet_id, cookie, csrf_token),
         {:ok, tweet} <- tweet_from_body(body) do
      {:ok, metadata_from_tweet(tweet)}
    end
  end

  def get_metadata(_url), do: {:error, :missing_url}

  def x_url?(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) ->
        host = String.downcase(host)

        host in ["x.com", "twitter.com"] or String.ends_with?(host, ".x.com") or
          String.ends_with?(host, ".twitter.com")

      _ ->
        false
    end
  rescue
    _error -> false
  end

  def x_url?(_url), do: false

  defp tweet_id(url) do
    with true <- x_url?(url),
         %URI{path: path} <- URI.parse(url),
         [_match, tweet_id] <- Regex.run(~r/(?:^|\/)(?:i\/)?status(?:es)?\/(\d+)/, path || "") do
      {:ok, tweet_id}
    else
      _ -> {:error, :missing_tweet_id}
    end
  rescue
    _error -> {:error, :missing_tweet_id}
  end

  defp twitter_cookie do
    cookie_path()
    |> File.read()
    |> case do
      {:ok, content} ->
        content
        |> Jason.decode()
        |> twitter_cookie_from_decoded()

      {:error, _reason} ->
        {:error, :missing_twitter_cookie}
    end
  end

  defp twitter_cookie_from_decoded({:ok, %{"twitter" => [cookie | _]}}) when is_binary(cookie),
    do: {:ok, cookie}

  defp twitter_cookie_from_decoded(_decoded), do: {:error, :missing_twitter_cookie}

  defp cookie_path do
    Application.get_env(:save_it, :cobalt_cookies_path, "cobalt-cookies.json")
  end

  defp csrf_token(cookie) do
    cookie
    |> cookie_pairs()
    |> Map.fetch("ct0")
    |> case do
      {:ok, csrf_token} when csrf_token != "" -> {:ok, csrf_token}
      _ -> {:error, :missing_twitter_cookie}
    end
  end

  defp cookie_pairs(cookie) do
    cookie
    |> String.split(";")
    |> Enum.map(&String.trim/1)
    |> Enum.reduce(%{}, fn pair, acc ->
      case String.split(pair, "=", parts: 2) do
        [key, value] -> Map.put(acc, key, value)
        _ -> acc
      end
    end)
  end

  defp fetch_tweet_result(url, tweet_id, cookie, csrf_token) do
    graphql_url = graphql_url()

    case Req.get(graphql_url,
           headers: request_headers(url, cookie, csrf_token),
           params: [
             variables:
               Jason.encode!(%{
                 tweetId: tweet_id,
                 withCommunity: false,
                 includePromotedContent: false,
                 withVoice: false
               }),
             features: Jason.encode!(feature_switches()),
             fieldToggles: Jason.encode!(field_toggles())
           ]
         ) do
      {:ok, %{status: status, body: body}} when status in 200..209 and is_map(body) ->
        {:ok, body}

      {:ok, %{status: status}} ->
        {:error, {:x_metadata_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp graphql_url do
    api_base_url()
    |> URI.merge("/i/api/graphql/#{tweet_result_query_id()}/TweetResultByRestId")
    |> URI.to_string()
  end

  defp api_base_url do
    Application.get_env(:save_it, :x_api_base_url, @default_api_base_url)
  end

  defp tweet_result_query_id do
    Application.get_env(:save_it, :x_tweet_result_query_id, @default_tweet_result_query_id)
  end

  defp request_headers(url, cookie, csrf_token) do
    [
      {"authorization", "Bearer #{bearer_token()}"},
      {"cookie", cookie},
      {"referer", url},
      {"user-agent", "Mozilla/5.0"},
      {"x-csrf-token", csrf_token},
      {"x-twitter-active-user", "yes"},
      {"x-twitter-auth-type", "OAuth2Session"},
      {"x-twitter-client-language", "en"}
    ]
  end

  defp bearer_token do
    Application.get_env(:save_it, :x_bearer_token, @default_bearer_token)
  end

  defp feature_switches do
    Map.new(@feature_switches, &{&1, true})
  end

  defp field_toggles do
    Map.new(@field_toggles, &{&1, true})
  end

  defp tweet_from_body(body) do
    result = get_in(body, ["data", "tweetResult", "result"])

    tweet =
      case result do
        %{"__typename" => "TweetWithVisibilityResults", "tweet" => tweet} -> tweet
        %{"legacy" => _legacy} = tweet -> tweet
        _ -> nil
      end

    case tweet do
      %{"legacy" => _legacy} -> {:ok, tweet}
      _ -> {:error, :missing_tweet_metadata}
    end
  end

  defp metadata_from_tweet(tweet) do
    legacy = Map.get(tweet, "legacy", %{})

    %{
      title: tweet_title(tweet),
      description: blank_to_nil(Map.get(legacy, "full_text")),
      keywords: tweet_keywords(legacy),
      image_url: tweet_image_url(legacy)
    }
  end

  defp tweet_title(tweet) do
    name = get_in(tweet, ["core", "user_results", "result", "core", "name"])
    screen_name = get_in(tweet, ["core", "user_results", "result", "core", "screen_name"])

    cond do
      is_binary(name) and name != "" and is_binary(screen_name) and screen_name != "" ->
        "#{name} (@#{screen_name}) on X"

      is_binary(screen_name) and screen_name != "" ->
        "@#{screen_name} on X"

      true ->
        "Post on X"
    end
  end

  defp tweet_keywords(legacy) do
    legacy
    |> get_in(["entities", "hashtags"])
    |> case do
      hashtags when is_list(hashtags) ->
        hashtags
        |> Enum.map(&Map.get(&1, "text"))
        |> Enum.filter(&(is_binary(&1) and &1 != ""))
        |> Enum.uniq()
        |> empty_list_to_nil()

      _ ->
        nil
    end
  end

  defp tweet_image_url(legacy) do
    legacy
    |> tweet_media()
    |> Enum.find_value(&Map.get(&1, "media_url_https"))
    |> blank_to_nil()
  end

  defp tweet_media(legacy) do
    get_in(legacy, ["extended_entities", "media"]) ||
      get_in(legacy, ["entities", "media"]) ||
      []
  end

  defp blank_to_nil(value) when is_binary(value) do
    if value == "", do: nil, else: value
  end

  defp blank_to_nil(_value), do: nil

  defp empty_list_to_nil([]), do: nil
  defp empty_list_to_nil(values), do: values
end
