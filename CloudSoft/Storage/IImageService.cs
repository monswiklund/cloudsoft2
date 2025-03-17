namespace CloudSoft.Storage;

public interface IImageService
{
    /// summary
    /// gets the URL for an image based on the specified image name
    /// /summary
    /// <param name="imageName">the name of the image</param>
    /// <returns>the URL of the image</returns>
    string GetImageUrl(string imageName);
}