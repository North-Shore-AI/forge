defmodule Forge.ArtifactStorage.LocalTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  alias Forge.ArtifactStorage.Local

  setup do
    # Create temporary directory for test artifacts
    base_path = Path.join(System.tmp_dir!(), "forge_test_artifacts_#{:rand.uniform(100_000)}")
    File.mkdir_p!(base_path)

    on_exit(fn ->
      # Cleanup test directory
      File.rm_rf!(base_path)
    end)

    %{base_path: base_path}
  end

  describe "put_blob/4" do
    test "stores blob and returns URI", %{base_path: base_path} do
      content = "Hello, World!"
      sample_id = "sample123"
      key = "test_artifact"

      {:ok, uri} = Local.put_blob(sample_id, key, content, base_path: base_path)

      assert uri =~ "file://"
      assert uri =~ base_path
    end

    test "uses content-addressable storage (same content = same URI)", %{base_path: base_path} do
      content = "Duplicate content"

      {:ok, uri1} = Local.put_blob("sample1", "key1", content, base_path: base_path)
      {:ok, uri2} = Local.put_blob("sample2", "key2", content, base_path: base_path)

      # Same content should produce same URI (deduplication)
      assert uri1 == uri2
    end

    test "different content produces different URIs", %{base_path: base_path} do
      {:ok, uri1} = Local.put_blob("sample1", "key1", "content1", base_path: base_path)
      {:ok, uri2} = Local.put_blob("sample2", "key2", "content2", base_path: base_path)

      assert uri1 != uri2
    end

    test "stores blob on filesystem", %{base_path: base_path} do
      content = "Test content"
      {:ok, uri} = Local.put_blob("sample1", "key1", content, base_path: base_path)

      # Extract path from URI and verify file exists
      path = String.replace_prefix(uri, "file://", "")
      assert File.exists?(path)
      assert File.read!(path) == content
    end

    test "handles large blobs", %{base_path: base_path} do
      # 1MB blob
      content = :crypto.strong_rand_bytes(1024 * 1024)
      {:ok, uri} = Local.put_blob("sample1", "large", content, base_path: base_path)

      assert is_binary(uri)
      path = String.replace_prefix(uri, "file://", "")
      assert File.exists?(path)
      assert byte_size(File.read!(path)) == byte_size(content)
    end
  end

  describe "get_blob/2" do
    test "retrieves stored blob", %{base_path: base_path} do
      content = "Stored content"
      {:ok, uri} = Local.put_blob("sample1", "key1", content, base_path: base_path)

      {:ok, retrieved} = Local.get_blob(uri, [])

      assert retrieved == content
    end

    test "returns error for non-existent blob", %{base_path: base_path} do
      fake_uri = "file://#{base_path}/nonexistent"

      {:error, :not_found} = Local.get_blob(fake_uri, [])
    end

    test "handles binary content", %{base_path: base_path} do
      content = <<1, 2, 3, 4, 5>>
      {:ok, uri} = Local.put_blob("sample1", "binary", content, base_path: base_path)

      {:ok, retrieved} = Local.get_blob(uri, [])

      assert retrieved == content
    end
  end

  describe "signed_url/2" do
    test "generates signed URL with expiry", %{base_path: base_path} do
      content = "Content for URL"
      {:ok, uri} = Local.put_blob("sample1", "key1", content, base_path: base_path)

      {:ok, signed_url} = Local.signed_url(uri, expires_in: 3600)

      assert signed_url =~ uri
      assert signed_url =~ "expires_in=3600"
    end

    test "uses default expiry if not specified", %{base_path: base_path} do
      content = "Content"
      {:ok, uri} = Local.put_blob("sample1", "key1", content, base_path: base_path)

      {:ok, signed_url} = Local.signed_url(uri, [])

      assert signed_url =~ "expires_in="
    end
  end

  describe "delete_blob/1" do
    test "deletes existing blob", %{base_path: base_path} do
      content = "To be deleted"
      {:ok, uri} = Local.put_blob("sample1", "key1", content, base_path: base_path)

      # Verify it exists
      path = String.replace_prefix(uri, "file://", "")
      assert File.exists?(path)

      # Delete it
      :ok = Local.delete_blob(uri)

      # Verify it's gone
      refute File.exists?(path)
    end

    test "succeeds when blob already deleted", %{base_path: base_path} do
      content = "Already deleted"
      {:ok, uri} = Local.put_blob("sample1", "key1", content, base_path: base_path)

      # Delete twice
      :ok = Local.delete_blob(uri)
      :ok = Local.delete_blob(uri)
    end

    test "succeeds for non-existent path" do
      fake_uri = "file:///tmp/nonexistent_blob_#{:rand.uniform(100_000)}"
      :ok = Local.delete_blob(fake_uri)
    end
  end

  describe "content-addressed deduplication" do
    test "multiple stores of same content only write once", %{base_path: base_path} do
      content = "Deduplicated content"

      {:ok, uri1} = Local.put_blob("sample1", "key1", content, base_path: base_path)
      {:ok, uri2} = Local.put_blob("sample2", "key2", content, base_path: base_path)
      {:ok, uri3} = Local.put_blob("sample3", "key3", content, base_path: base_path)

      # All URIs should be identical
      assert uri1 == uri2
      assert uri2 == uri3

      # Verify only one file exists
      blob_dir = Path.join(base_path, "blobs")
      files = File.ls!(blob_dir)
      assert length(files) == 1
    end
  end

  describe "integration with file system" do
    test "creates blob directory if it doesn't exist" do
      base_path = Path.join(System.tmp_dir!(), "forge_new_dir_#{:rand.uniform(100_000)}")
      refute File.exists?(base_path)

      content = "Test"
      {:ok, _uri} = Local.put_blob("sample1", "key1", content, base_path: base_path)

      assert File.exists?(Path.join(base_path, "blobs"))

      # Cleanup
      File.rm_rf!(base_path)
    end
  end
end
