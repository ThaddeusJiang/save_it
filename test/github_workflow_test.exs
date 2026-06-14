defmodule SaveIt.GitHubWorkflowTest do
  use ExUnit.Case, async: true

  @docker_publish_workflow ".github/workflows/docker-publish.yml"

  test "publishes a floating stag tag for prerelease images" do
    workflow = File.read!(@docker_publish_workflow)

    assert workflow =~ "type=raw,value=stag,enable=${{ inputs.is_prerelease }}"
  end

  test "publishes latest only for stable release images" do
    workflow = File.read!(@docker_publish_workflow)

    assert workflow =~ "type=raw,value=latest,enable=${{ !inputs.is_prerelease }}"
  end
end
