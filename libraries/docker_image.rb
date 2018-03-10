module DockerCookbook
  class DockerImage < DockerBase
    resource_name :docker_image

    # Modify the default of read_timeout from 60 to 120
    property :read_timeout, default: 120, desired_state: false

    # https://docs.docker.com/engine/api/v1.35/#tag/Image
    property :destination, [String, nil]
    property :force, Boolean, default: false
    property :host, [String, nil], default: lazy { default_host }, desired_state: false
    property :nocache, Boolean, default: false
    property :noprune, Boolean, default: false
    property :repo, String, name_property: true
    property :rm, Boolean, default: true
    property :source, String
    property :tag, String, default: 'latest'

    alias image repo
    alias image_name repo
    alias no_cache nocache
    alias no_prune noprune

    #########
    # Actions
    #########

    default_action :pull

    action :build do
      converge_by "Build image #{image_identifier}" do
        build_image
      end
    end

    action :build_if_missing do
      return if Docker::Image.exist?(image_identifier, {}, connection)
      action_build
    end

    action :import do
      return if Docker::Image.exist?(image_identifier, {}, connection)
      converge_by "Import image #{image_identifier}" do
        import_image
      end
    end

    action :pull do
      # We already did the work, but we need to report what we did!
      converge_by "Pull image #{image_identifier}" do
      end if pull_image
    end

    action :pull_if_missing do
      return if Docker::Image.exist?(image_identifier, {}, connection)
      action_pull
    end

    action :push do
      converge_by "Push image #{image_identifier}" do
        push_image
      end
    end

    action :remove do
      return unless Docker::Image.exist?(image_identifier, {}, connection)
      converge_by "Remove image #{image_identifier}" do
        remove_image
      end
    end

    action :save do
      converge_by "Save image #{image_identifier}" do
        save_image
      end
    end

    action :load do
      converge_by "load image #{image_identifier}" do
        load_image
      end
    end

    declare_action_class.class_eval do
      ################
      # Helper methods
      ################

      def build_from_directory
        i = Docker::Image.build_from_dir(
          new_resource.source,
          {
            'nocache' => new_resource.nocache,
            'rm' => new_resource.rm,
          },
          connection
        )
        i.tag('repo' => new_resource.repo, 'tag' => new_resource.tag, 'force' => new_resource.force)
      end

      def build_from_dockerfile
        i = Docker::Image.build(
          IO.read(new_resource.source),
          {
            'nocache' => new_resource.nocache,
            'rm' => new_resource.rm,
          },
          connection
        )
        i.tag('repo' => new_resource.repo, 'tag' => new_resource.tag, 'force' => new_resource.force)
      end

      def build_from_tar
        i = Docker::Image.build_from_tar(
          ::File.open(new_resource.source, 'r'),
          {
            'nocache' => new_resource.nocache,
            'rm' => new_resource.rm,
          },
          connection
        )
        i.tag('repo' => new_resource.repo, 'tag' => new_resource.tag, 'force' => new_resource.force)
      end

      def build_image
        if ::File.directory?(new_resource.source)
          build_from_directory
        elsif ::File.extname(new_resource.source) == '.tar'
          build_from_tar
        else
          build_from_dockerfile
        end
      end

      def image_identifier
        "#{new_resource.repo}:#{new_resource.tag}"
      end

      def import_image
        with_retries do
          i = Docker::Image.import(new_resource.source, {}, connection)
          i.tag('repo' => new_resource.repo, 'tag' => new_resource.tag, 'force' => new_resource.force)
        end
      end

      def pull_image
        with_retries do
          creds = credentails
          original_image = Docker::Image.get(image_identifier, {}, connection) if Docker::Image.exist?(image_identifier, {}, connection)
          new_image = Docker::Image.create({ 'fromImage' => image_identifier }, creds, connection)

          !(original_image && original_image.id.start_with?(new_image.id))
        end
      end

      def push_image
        with_retries do
          creds = credentails
          i = Docker::Image.get(image_identifier, {}, connection)
          i.push(creds, repo_tag: image_identifier)
        end
      end

      def remove_image
        with_retries do
          i = Docker::Image.get(image_identifier, {}, connection)
          i.remove(force: new_resource.force, noprune: new_resource.noprune)
        end
      end

      def save_image
        with_retries do
          Docker::Image.save(new_resource.repo, new_resource.destination, connection)
        end
      end

      def load_image
        with_retries do
          Docker::Image.load(new_resource.source, {}, connection)
        end
      end

      def credentails
        registry_host = parse_registry_host(new_resource.repo)
        creds = node.run_state['docker_auth'] && node.run_state['docker_auth'][registry_host] || (node.run_state['docker_auth'] ||= {})['index.docker.io']
        creds
      end
    end
  end
end
