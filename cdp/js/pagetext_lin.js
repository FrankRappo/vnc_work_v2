(function(){
 var b=document.body?document.body.innerText:'';
 b=b.replace(/[ \t\xa0]+/g,' ').replace(/\n{2,}/g,'\n');
 return 'URL='+location.href+'\nTITLE='+document.title+'\n'+b.slice(0,3000);
})()
