$main_link="https://gogoanime.ar"
function create_aes($key){
    $aes=New-Object "System.Security.Cryptography.AesManaged"
    $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
    $aes.IV = [System.Text.Encoding]::UTF8.GetBytes("3134003223491201")
    $aes.Key = [System.Text.Encoding]::UTF8.GetBytes($key)
    $aes
}

function aes_encrypt($plaintext){
    #convert to bytes
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($plaintext)
    $aes= create_aes "37911490979715163134003223491201"
    $encryptor = $aes.CreateEncryptor()
    $encrypted_data = $encryptor.TransformFinalBlock($bytes, 0, $bytes.Length);
    [System.Convert]::ToBase64String($encrypted_data)

}
function aes_decrypt($key,$encrypted_text){
    $bytes = [System.Convert]::FromBase64String($encrypted_text)
    $aes = create_aes $key
    $decryptor=$aes.CreateDecryptor()
    $decrypted_data = $decryptor.TransformFinalBlock($bytes, 16, $bytes.Length - 16);
    [System.Text.Encoding]::UTF8.GetString($decrypted_data).Trim([char]0)
}

function get_group($pattern,$content){
    $match = Select-String $pattern -InputObject $content

    $match.matches.groups[1].value
}
function get_re($pattern,$content){
    $match = Select-String $pattern -InputObject $content
    $match.matches.groups[0].value
}

function search_anime($name){
    $name = $name.Replace(" ","%20")
    $search_url=$search_url=$main_link+"/search.html?keyword=$name"
    $response = Invoke-WebRequest -Uri $search_url
    $anime_results = $response.ParsedHtml.getElementsByClassName('name') | ForEach-Object { $_.getElementsByTagName('a')} |Select-Object -Expand nameProp
    
    Write-Host "[*]Results: "
    for($i=0;$i -le ($anime_results.Length -1);$i++){
        Write-Host $i":" -NoNewline
        Write-Host $anime_results[$i]
    }

    $p = Read-Host -Prompt "[*]Enter index"
    $anime_results[$p]
}

function search_ep($name){
    $link=$main_link+"/category/$name"
    $response = Invoke-WebRequest -Uri $link
    $eps = get_group "ep_start = '0' ep_end = '(\d+)'>" $response.Content
    $ep_to_watch = Read-Host -Prompt "[*]Available Episode(1-$eps)"
    [string]$ep_to_watch 
}

function get_streaming_link($link){
    $j=0
    $response = Invoke-WebRequest -Uri $link
    $qualities = Select-String "RESOLUTION=[0-9]+x([0-9]+)" -InputObject [string]$response.rawcontent -AllMatches | ForEach-Object {$_.matches.Groups.value}
    $l = Select-String ".*\.m3u8" -InputObject $response.rawcontent -AllMatches | ForEach-Object {$_.matches.Groups.value}
    for($i=1;$i -le ($qualities.Length -1) ; $i+=2){
        Write-Host $j":" -NoNewline
        Write-Host $qualities[$i]"p"
        $j++
    }
    $p = Read-Host -Prompt "[*]Enter your choice"
    $f_link = $l[$p]
    if($f_link -match "https://"){
        $f_link = $f_link
    }
    else{
        $f_link = $link.Replace($link.Split("/")[-1],$f_link)
    }

    $f_link
}

$name=Read-Host -Prompt "[*]Enter anime name"
$anime_to_watch =search_anime $name
$ep_to_watch = search_ep $anime_to_watch

$link=$main_link+"/$anime_to_watch-episode-$ep_to_watch"
$Response=Invoke-WebRequest -URI $link

$gogo_link = "https:" + (get_group 'data-video=\"(//gogohd.net/streaming.php?.*)\" >' $Response.Content)
$gogo_id = get_group 'id=(.*)\&' $gogo_link


#get request to the gogolink
$Response=Invoke-WebRequest -Uri $gogo_link
$crypto_data= get_group 'data-value=\"(.*)\"' $Response.Content

$raw_crypto = (aes_decrypt "37911490979715163134003223491201" $crypto_data)
$full_cryptodata = get_re '\&mip=.*' $raw_crypto


$id= aes_encrypt $gogo_id

#make ajax request
$full_payload="$id$full_cryptodata&alias=$gogo_id"

$header=@{
    'x-requested-with' = 'XMLHttpRequest'
}

$response= Invoke-WebRequest -Uri "https://gogohd.net/encrypt-ajax.php?id=$full_payload" -Headers $header

$x = $response.Content | ConvertFrom-Json

$link = (aes_decrypt "54674138327930866480207815084989" $x[0].data).Trim("\\\\")
$final_link = (get_group 'file\":\"([^\"]*)' $link).Replace('\/','/')
#Write-Host $final_link
$final_streaming = get_streaming_link $final_link
Start-Process mpv -ArgumentList "$final_streaming --force-media-title='$anime_to_watch-ep-$ep_to_watch'"
