using CloudSoft.Configurations;
using Microsoft.Extensions.Options;

namespace CloudSoft.Services;

public class AzureBlobImageService
{
    private readonly string _blobContainerUrl;
    
    public AzureBlobImageService(IOptions<AzureBlobOptions> options)
    {
        _blobContainerUrl = options.Value.ContainerUrl;
    }
    
    
    // Azure blob storage URLS are Case sensitive
    // for production, images will be served directly from the blob storage CDN
    // CDN = Content Delivery Network
    // Content Delivery Network is a system of distributed servers that deliver webpages and other web content to a user based on the geographic locations of the user,
    // the origin of the webpage and a content delivery server.
    public string GetImageUrl(string imageName)
    {
        return $"{_blobContainerUrl}/{imageName}";
    }
}